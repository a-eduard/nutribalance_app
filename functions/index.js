/* eslint-disable max-len */
// Cloud Functions для «Моя Ева».
//
// Главное в этой версии:
//  • Чат между пользователями стал устойчивым к VPN/роумингу: сервер сам
//    ведёт счётчики непрочитанных, превью, пуши; есть HTTPS-фолбэк для
//    отправки (sendChatMessage) и получения (fetchChatMessages).
//  • Публичные профили (public_profiles) — поиск и список чатов больше не
//    требуют читать чужие приватные документы users (данные о здоровье).
//  • Ева (askDietitian): проверка авторизации, лимиты считаются на сервере,
//    ответ сохраняется в Firestore сервером (не теряется, если закрыть экран),
//    ретраи Gemini, фото читаются из Storage (без двойной загрузки).
//  • Покупки: сервер больше не выдаёт Premium любому, кто вызовет функцию —
//    проверка продукта, защита от повторного использования покупки,
//    правильное продление срока. Промокоды — на сервере.
//  • Новое: weeklyInsights — «Итоги недели от Евы».

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const auth = require("firebase-functions/v1/auth");
// ВАЖНО: firebase-admin v14 больше не поддерживает старый API admin.firestore()/admin.messaging().
// Из-за этого в прошлой версии функций пуши о новых сообщениях НЕ отправлялись вообще
// (TypeError молча перехватывался), а очистка данных при удалении аккаунта падала.
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, FieldPath, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");
const { GoogleGenerativeAI } = require("@google/generative-ai");

initializeApp();

const db = getFirestore();

const geminiKey = defineString("GEMINI_API_KEY");

// Ключи RuStore (из .env) — оставлены для будущей серверной проверки через прокси в РФ.
// eslint-disable-next-line no-unused-vars
const ruStoreKeyId = defineString("RUSTORE_KEY_ID", { default: "" });
// eslint-disable-next-line no-unused-vars
const ruStorePrivateKey = defineString("RUSTORE_PRIVATE_KEY", { default: "" });

const SUPPORT_ADMIN_UID = "VlTTLh2o7GVaXUzw32sNUtQ6alD3";
const FREE_LIMITS = { message: 5, scan: 3 };

// Модель меняется в functions/.env (GEMINI_MODEL) без правки кода и без релиза приложения.
// С 01.12.2026 Google переводит gemini-2.5-flash на gemini-3.5-flash-lite.
const geminiModelParam = defineString("GEMINI_MODEL", { default: "gemini-2.5-flash" });
// Только для временной проверки моделей (функция aiProbe). Пусто — проверка выключена.
const probeToken = defineString("AI_PROBE_TOKEN", { default: "" });

function geminiModel() {
  return (geminiModelParam.value() || "gemini-2.5-flash").trim();
}

/**
 * Настройки генерации под семейство модели.
 * think: "off" — без размышлений (переписка), "low" — немного (фото, анализы), "medium".
 * У Gemini 2.x — temperature и thinkingBudget; у Gemini 3.x — thinkingLevel,
 * temperature Google просит не передавать (а оба вида thinking вместе дают ошибку 400).
 */
function genConfig({ temperature, think = "off", json = false } = {}, model = geminiModel()) {
  const cfg = {};
  if (json) cfg.responseMimeType = "application/json";
  if (/^gemini-2\./.test(model)) {
    if (typeof temperature === "number") cfg.temperature = temperature;
    cfg.thinkingConfig = { thinkingBudget: think === "off" ? 0 : think === "low" ? 1024 : 4096 };
  } else {
    // Gemini 3.7+ Flash не принимает "minimal" (ошибка 400) — для них самый низкий уровень "low".
    const noMinimal = /^gemini-3\.([7-9]|\d{2,})/.test(model) || /^gemini-[4-9]/.test(model);
    const level = think === "off" ? (noMinimal ? "low" : "minimal") : think;
    cfg.thinkingConfig = { thinkingLevel: level };
  }
  return cfg;
}

function getGenAI() {
  return new GoogleGenerativeAI(geminiKey.value());
}

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Нужна авторизация.");
  }
  return request.auth.uid;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function toInt(v, def = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n) : def;
}

function isProActive(data) {
  if (!data || data.isPro !== true) return false;
  const until = data.proUntil;
  if (until && typeof until.toDate === "function") return until.toDate() > new Date();
  return true;
}

async function isAdmin(uid) {
  if (uid === SUPPORT_ADMIN_UID) return true;
  try {
    const g = await db.collection("app_settings").doc("globals").get();
    return g.exists && g.data().specialist_uid === uid;
  } catch (e) {
    return false;
  }
}

// ==========================================
// 1. ОЧИСТКА ДАННЫХ ПРИ УДАЛЕНИИ АККАУНТА
// ==========================================
exports.cleanupOnAccountDelete = auth.user().onDelete(async (user) => {
  const uid = user.uid;
  try {
    const chatsSnap = await db.collection("chats").where("users", "array-contains", uid).get();
    for (const chatDoc of chatsSnap.docs) {
      await deleteCollectionInBatches(chatDoc.ref.collection("messages"));
      await chatDoc.ref.delete();
    }

    const userRef = db.collection("users").doc(uid);
    const subcollections = await userRef.listCollections();
    for (const subcoll of subcollections) await deleteCollectionInBatches(subcoll);
    await userRef.delete();
    await db.collection("public_profiles").doc(uid).delete().catch(() => null);
    await db.collection("welcome_queue").doc(uid).delete().catch(() => null);
    await getStorage().bucket().deleteFiles({ prefix: `users/${uid}/` });
  } catch (error) {
    console.error(`[cleanupOnAccountDelete] ERROR for ${uid}:`, error);
  }
});

async function deleteCollectionInBatches(collectionRef) {
  let snapshot = await collectionRef.limit(400).get();
  while (snapshot.size > 0) {
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    snapshot = await collectionRef.limit(400).get();
  }
}

// ==========================================
// 2. PUSH-УВЕДОМЛЕНИЯ
// ==========================================
async function sendPush(uid, title, body, dataPayload = {}) {
  try {
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists || !userDoc.data().fcmToken) return;
    const data = {};
    Object.keys(dataPayload).forEach((k) => {
      if (dataPayload[k] !== undefined && dataPayload[k] !== null) data[k] = String(dataPayload[k]);
    });
    const androidNotification = { channelId: "high_importance_channel", sound: "default" };
    if (data.chatId) androidNotification.tag = data.chatId; // новые сообщения одного чата «схлопываются»
    await getMessaging().send({
      token: userDoc.data().fcmToken,
      notification: { title: String(title).slice(0, 120), body: String(body || "").slice(0, 240) },
      android: { priority: "high", notification: androidNotification },
      apns: { payload: { aps: { sound: "default" } } },
      data,
    });
  } catch (error) {
    const code = error && error.code;
    if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
      await db.collection("users").doc(uid).update({ fcmToken: FieldValue.delete() }).catch(() => null);
    } else {
      console.error("[sendPush]", uid, error);
    }
  }
}

exports.notifyOnNewNotification = onDocumentCreated("users/{userId}/notifications/{notificationId}", async (event) => {
  const notifData = event.data && event.data.data();
  if (notifData) {
    await sendPush(event.params.userId, notifData.title || "Новое уведомление", notifData.body || "", { type: notifData.type || "general" });
  }
});

// ==========================================
// 3. ПУБЛИЧНЫЕ ПРОФИЛИ (поиск и список чатов)
// ==========================================
function publicProjection(data) {
  const name = String((data && data.name) || "").trim();
  const lastName = String((data && data.lastName) || "").trim();
  const full = [name, lastName].filter(Boolean).join(" ") || "Пользователь";
  const photo = String((data && data.photoUrl) || "");
  return {
    name: name || "Пользователь",
    lastName,
    nameLower: full.toLowerCase(),
    nickname: String((data && data.nickname) || "").trim().toLowerCase(),
    photoUrl: photo.startsWith("http") ? photo : "",
  };
}

function sameProjection(a, b) {
  return ["name", "lastName", "nameLower", "nickname", "photoUrl"].every((k) => (a || {})[k] === (b || {})[k]);
}

exports.syncPublicProfile = onDocumentWritten("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  const ref = db.collection("public_profiles").doc(uid);
  if (!after) {
    await ref.delete().catch(() => null);
    return;
  }
  const before = event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const next = publicProjection(after);
  if (before && sameProjection(publicProjection(before), next)) {
    // Проверим, что документ вообще существует (бэкфилл старых аккаунтов).
    const existing = await ref.get();
    if (existing.exists) return;
  }
  await ref.set({ ...next, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
});

exports.backfillPublicProfiles = onCall({ timeoutSeconds: 540, memory: "512MiB" }, async (request) => {
  const uid = requireAuth(request);
  if (!(await isAdmin(uid))) throw new HttpsError("permission-denied", "Только для администратора.");
  let count = 0;
  let last = null;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = db.collection("users").orderBy(FieldPath.documentId()).limit(300);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => {
      batch.set(db.collection("public_profiles").doc(d.id), { ...publicProjection(d.data()), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      count++;
    });
    await batch.commit();
    last = snap.docs[snap.docs.length - 1];
  }
  return { ok: true, count };
});

// ==========================================
// 4. ЧАТ МЕЖДУ ПОЛЬЗОВАТЕЛЯМИ
// ==========================================
const ALLOWED_CHAT_COLLECTIONS = new Set(["chats"]);

function parseChat(chatId, uid) {
  if (typeof chatId !== "string" || !/^[A-Za-z0-9]{6,64}_[A-Za-z0-9]{6,64}$/.test(chatId)) {
    throw new HttpsError("invalid-argument", "Некорректный chatId.");
  }
  const users = chatId.split("_");
  if (!users.includes(uid)) throw new HttpsError("permission-denied", "Нет доступа к этому чату.");
  const other = users.find((u) => u !== uid) || uid;
  return { users, other };
}

async function participantInfo(uid) {
  try {
    const d = await db.collection("users").doc(uid).get();
    const p = publicProjection(d.exists ? d.data() : {});
    return { name: [p.name, p.lastName].filter(Boolean).join(" "), photoUrl: p.photoUrl };
  } catch (e) {
    return { name: "Пользователь", photoUrl: "" };
  }
}

/** Отправка через HTTPS — когда поток Firestore у клиента «залип» (VPN, роуминг). */
exports.sendChatMessage = onCall({ maxInstances: 20 }, async (request) => {
  const uid = requireAuth(request);
  const { chatId, messageId, text, imageUrl } = request.data || {};
  const collection = (request.data && request.data.collection) || "chats";
  if (!ALLOWED_CHAT_COLLECTIONS.has(collection)) throw new HttpsError("invalid-argument", "Некорректная коллекция.");
  const { other } = parseChat(chatId, uid);

  if (typeof messageId !== "string" || !/^[A-Za-z0-9]{10,40}$/.test(messageId)) {
    throw new HttpsError("invalid-argument", "Некорректный messageId.");
  }
  const cleanText = String(text || "").trim().slice(0, 4000);
  const cleanImage = typeof imageUrl === "string" && imageUrl.startsWith("https://firebasestorage.googleapis.com/") ? imageUrl : null;
  if (!cleanText && !cleanImage) throw new HttpsError("invalid-argument", "Пустое сообщение.");

  const msgRef = db.collection(collection).doc(chatId).collection("messages").doc(messageId);
  try {
    await msgRef.create({
      senderId: uid,
      receiverId: other,
      text: cleanText,
      type: cleanImage ? "image" : "text",
      ...(cleanImage ? { imageUrl: cleanImage } : {}),
      timestamp: FieldValue.serverTimestamp(),
      clientTs: Timestamp.now(),
      v: 2,
      via: "https",
    });
  } catch (e) {
    // ALREADY_EXISTS — сообщение уже дошло через Firestore. Это не ошибка.
    if (e.code !== 6) throw new HttpsError("internal", "Не удалось сохранить сообщение.");
  }
  return { ok: true };
});

/** Получение последних сообщений через HTTPS (резерв для «молчащего» потока). */
exports.fetchChatMessages = onCall({ maxInstances: 20 }, async (request) => {
  const uid = requireAuth(request);
  const collection = (request.data && request.data.collection) || "chats";
  if (!ALLOWED_CHAT_COLLECTIONS.has(collection)) throw new HttpsError("invalid-argument", "Некорректная коллекция.");
  parseChat(request.data && request.data.chatId, uid);
  const limit = Math.min(Math.max(toInt(request.data && request.data.limit, 60), 1), 100);

  const snap = await db.collection(collection).doc(request.data.chatId).collection("messages")
    .orderBy("timestamp", "desc").limit(limit).get();
  const messages = snap.docs.map((d) => {
    const m = d.data();
    const ts = m.timestamp && m.timestamp.toMillis ? m.timestamp.toMillis() : (m.clientTs && m.clientTs.toMillis ? m.clientTs.toMillis() : Date.now());
    return {
      id: d.id,
      senderId: m.senderId || "",
      text: m.text || "",
      imageUrl: m.imageUrl || null,
      ts,
      edited: m.edited === true,
    };
  });
  return { messages };
});

/** Новое сообщение: счётчик непрочитанных, превью в списке, пуш получателю. */
exports.onNewChatMessage = onDocumentCreated("chats/{chatId}/messages/{messageId}", async (event) => {
  const messageData = event.data && event.data.data();
  if (!messageData) return;
  const senderId = messageData.senderId;
  const chatId = event.params.chatId;
  const recipientId = chatId.split("_").find((id) => id !== senderId);
  if (!recipientId || !senderId) return;

  const preview = messageData.text && String(messageData.text).trim() ? String(messageData.text).trim() : (messageData.imageUrl ? "📷 Фото" : "Новое сообщение");
  const senderInfo = await participantInfo(senderId);

  // Новые клиенты (v2) не увеличивают счётчик сами — это делает сервер атомарно.
  if (messageData.v === 2) {
    try {
      const recipientInfo = await participantInfo(recipientId);
      await db.collection("chats").doc(chatId).set({
        users: [senderId, recipientId],
        lastMessage: preview.slice(0, 200),
        lastSenderId: senderId,
        lastUpdated: FieldValue.serverTimestamp(),
        lastMessageTime: FieldValue.serverTimestamp(),
        [`unread_${recipientId}`]: FieldValue.increment(1),
        participant_info: { [senderId]: senderInfo, [recipientId]: recipientInfo },
      }, { merge: true });
    } catch (e) {
      console.error("[onNewChatMessage] meta update failed", e);
    }
  }

  await sendPush(recipientId, senderInfo.name || "Новое сообщение", preview, {
    type: "chat",
    chatId,
    senderId,
    senderName: senderInfo.name || "Собеседник",
  });
});

// ==========================================
// 4б. ПРИВЕТСТВИЕ НОВОМУ ПОЛЬЗОВАТЕЛЮ ОТ СЛУЖБЫ ЗАБОТЫ
// ==========================================
// Текст меняется здесь; после правки — деплой функций.
const WELCOME_TEXT = `Здравствуйте! 👋 Добро пожаловать! Я Мария, менеджер службы заботы пользователей.
Мы сейчас активно развиваем приложение и собираем отзывы от наших первых пользователей. Буду очень благодарна, если вы поделитесь впечатлениями: всё ли удобно нажимается, понятен ли интерфейс, чего вам не хватает? Не забудьте применить промокод START3.

Пишите сюда любые технические пожелания или вопросы — я всегда на связи и мы с радостью поможем сделать приложение лучше для вас!`;

/**
 * Срабатывает один раз при создании аккаунта. Кладёт сообщение от аккаунта поддержки
 * в обычный чат с поддержкой; счётчик непрочитанных и пуш делает onNewChatMessage.
 * Фиксированный ID сообщения — повторный запуск не создаст дубль.
 */
/** Кладёт приветствие от службы заботы в чат с поддержкой (идемпотентно). */
async function createWelcomeMessage(uid) {
  const chatId = [uid, SUPPORT_ADMIN_UID].sort().join("_");
  const msgRef = db.collection("chats").doc(chatId).collection("messages").doc("welcome_v1");
  try {
    await msgRef.create({
      senderId: SUPPORT_ADMIN_UID,
      receiverId: uid,
      text: WELCOME_TEXT,
      type: "text",
      timestamp: FieldValue.serverTimestamp(),
      clientTs: Timestamp.now(),
      v: 2,
      via: "welcome",
    });
  } catch (e) {
    if (e.code === 6) return; // уже отправлено
    throw e;
  }
}

const WELCOME_DELAY_MS = 30 * 60 * 1000;

/**
 * При регистрации ставим приветствие в очередь: оно придёт через 30 минут,
 * когда пользователь уже прошёл анкету и познакомился с Евой
 * (раньше приходило сразу и перебивало онбординг). Отправляет processWelcomeQueue.
 */
exports.sendWelcomeMessage = auth.user().onCreate(async (user) => {
  const uid = user && user.uid;
  if (!uid || uid === SUPPORT_ADMIN_UID) return;
  try {
    await db.collection("welcome_queue").doc(uid).set({
      dueAt: Timestamp.fromMillis(Date.now() + WELCOME_DELAY_MS),
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("[sendWelcomeMessage] queue failed", e.code || "", e.message || "");
  }
});

// ==========================================
// 5. EVA — ИИ-НУТРИЦИОЛОГ
// ==========================================
const EVA_SYSTEM_PROMPT = `Ты — Ева, элитный нутрициолог, велнес-ментор и заботливая ИИ-подруга в приложении «Моя Ева». Твоя цель — помогать с питанием, женским здоровьем и образом жизни.

КРИТИЧЕСКИ ВАЖНЫЕ ПРАВИЛА:
1. ИДЕНТИФИКАЦИЯ: Тебя зовут Ева. Пользователя зовут так, как указано в досье. Никогда не называй пользователя Евой. Обращайся по имени или на «ты».
2. ЧУЖИЕ ДАННЫЕ: Если анализы/документы принадлежат другому человеку (дочери, мужу), оценивай их как отдельного пациента. НЕ применяй к ним цель пользователя и фазу его цикла.
3. СМЕНА ТЕМЫ: Если пользователь меняет тему — сразу переключайся. Не требуй файлы, которые просила раньше.
4. ФАЙЛЫ В ИСТОРИИ: пометка «[СИСТЕМНОЕ СООБЩЕНИЕ: ...прикреплял файлы...]» означает, что ты уже видела эти файлы. Не проси прислать их снова.
5. ТОН: не здоровайся в каждом сообщении, сразу к сути. Тепло, на «ты», в женском роде. Уточняющие вопросы — по делу.
6. ПРОДУКТЫ: предлагай блюда из простых продуктов, доступных в обычных супермаркетах России и СНГ.
7. БЕЗОПАСНОСТЬ: ты не врач. При тревожных симптомах мягко советуй обратиться к специалисту. Никаких жёстких диет для беременных.

СЦЕНАРИИ:
- Оценка еды (фото/текст): очень коротко — 1 предложение поддержки, КБЖУ и обязательный JSON-блок.
- JSON log_food добавляй ТОЛЬКО когда пользователь сообщает, что УЖЕ съела что-то, или присылает фото своей еды. В меню, рецептах и советах «что съесть» log_food НЕ добавляй. В одном ответе — не больше одного JSON-блока. Еду, о которой пользователь уже писал раньше в этой переписке, повторно НЕ записывай: она уже в дневнике — просто ответь на вопрос.
- Анализы: объясни простым языком, дай общие рекомендации по питанию и ОБЯЗАТЕЛЬНО последней фразой напомни, что диагноз и лечение назначает врач.
- Рецепты: вступление (1 предложение), ингредиенты, шаги и блок [SHOPPING_LIST].

ТЕХНИЧЕСКИЕ ПРАВИЛА JSON (для интерфейса). Сначала текст ответа, В САМОМ КОНЦЕ — JSON:
- Обновление цели КБЖУ:
\`\`\`json
{ "action_type": "update_goal", "coach_message": "Цель обновлена! ✨", "calories": 2000, "protein": 150, "fat": 65, "carbs": 200 }
\`\`\`
- Добавление еды (ВСЕГДА разбивай блюдо на базовые компоненты, для каждого — целые числа, "health_score" 1-10 и "fiber"; на верхнем уровне обязательно "meal_name"):
\`\`\`json
{"action_type": "log_food", "meal_name": "Лосось с брокколи", "coach_message": "Добавила в дневник! 🌸", "items": [{"meal_name": "Лосось", "weight_g": 150, "calories": 250, "protein": 25, "fat": 15, "carbs": 0, "fiber": 0, "health_score": 9}]}
\`\`\`
- Список покупок (без markdown, только текст внутри тегов):
[SHOPPING_LIST]
{"items": [{"name": "Гречка", "amount": "200 г", "category": "Бакалея"}]}
[/SHOPPING_LIST]`;

/** Доп. правила для «Что съесть?» — короткое меню без записи в дневник. */
const MEAL_PLAN_RULES = `

РЕЖИМ «ЧТО СЪЕСТЬ»: пользователь просит идеи меню, а НЕ записывает еду. Не добавляй JSON log_food и update_goal.
Формат: для каждого блюда — заголовок с названием, одна строка «≈ ккал · Б/Ж/У», ингредиенты с граммовкой одной строкой, приготовление в 2–3 коротких шага. Без длинных вступлений и заключений. В самом конце — блок [SHOPPING_LIST].`;

/** Атомарно списывает бесплатную попытку. Premium с действующим сроком — без ограничений. */
async function consumeQuota(uid, kind) {
  const field = kind === "scan" ? "free_scans_left" : "free_messages_left";
  const def = FREE_LIMITS[kind] || 5;
  const ref = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    if (isProActive(data)) return { allowed: true, pro: true };
    if (data.isPro === true && data.proUntil) {
      tx.set(ref, { isPro: false }, { merge: true }); // срок подписки истёк
    }
    const left = Number.isFinite(Number(data[field])) ? Number(data[field]) : def;
    if (left <= 0) return { allowed: false, pro: false, left: 0 };
    tx.set(ref, { [field]: left - 1 }, { merge: true });
    return { allowed: true, pro: false, left: left - 1, field };
  });
}

async function refundQuota(uid, quotaResult) {
  if (!quotaResult || quotaResult.pro || !quotaResult.field) return;
  await db.collection("users").doc(uid).set({ [quotaResult.field]: FieldValue.increment(1) }, { merge: true }).catch(() => null);
}

async function loadStorageBase64(uid, path, maxBytes) {
  if (typeof path !== "string" || !path.startsWith(`users/${uid}/`) || path.includes("..")) {
    throw new HttpsError("permission-denied", "Файл недоступен.");
  }
  const file = getStorage().bucket().file(path);
  const [meta] = await file.getMetadata();
  if (Number(meta.size || 0) > maxBytes) throw new HttpsError("invalid-argument", "Файл слишком большой.");
  const [buf] = await file.download();
  return buf.toString("base64");
}

async function loadServerHistory(uid, botType) {
  const snap = await db.collection("users").doc(uid).collection(`ai_chats_${botType}`)
    .orderBy("timestamp", "desc").limit(12).get();
  return snap.docs.reverse().map((d) => {
    const m = d.data();
    let text = String(m.text || "");
    if ((Array.isArray(m.imageUrls) && m.imageUrls.length) || m.pdfUrl) {
      text = `[СИСТЕМНОЕ СООБЩЕНИЕ: В этом запросе пользователь прикреплял файлы/анализы. Опирайся на то, что уже увидела.]\n${text}`;
    }
    return { role: m.role === "ai" ? "model" : "user", text };
  });
}

function cleanHistory(history) {
  const out = [];
  let expected = "user";
  for (const msg of (Array.isArray(history) ? history : []).slice(-14)) {
    const role = (msg.role === "ai" || msg.role === "assistant" || msg.role === "model") ? "model" : "user";
    const text = String(msg.text || (msg.parts && msg.parts[0] && msg.parts[0].text) || "").slice(0, 6000);
    if (role === expected && text.trim().length > 0) {
      out.push({ role, parts: [{ text }] });
      expected = expected === "user" ? "model" : "user";
    }
  }
  if (out.length > 0 && out[out.length - 1].role !== "model") out.pop();
  return out;
}

async function generateWithRetry(fn) {
  let lastErr;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      const msg = String((e && e.message) || "");
      const retriable = /429|500|503|overloaded|unavailable|deadline|timeout|fetch failed/i.test(msg);
      if (!retriable) break;
      await sleep(800 * Math.pow(2, attempt));
    }
  }
  throw lastErr;
}

exports.askDietitian = onCall({ cors: true, maxInstances: 20, timeoutSeconds: 120, memory: "512MiB" }, async (request) => {
  const uid = requireAuth(request);
  const data = request.data || {};
  const prompt = String(data.prompt || "").slice(0, 12000);
  const userContext = String(data.userContext || "").slice(0, 8000);
  const botType = typeof data.botType === "string" && /^[a-z_]{1,32}$/.test(data.botType) ? data.botType : null;
  const saveReply = data.saveReply === true && !!botType;
  const quotaKind = data.quota === "scan" || data.quota === "message" ? data.quota : null;
  const mode = data.mode === "meal_plan" ? "meal_plan" : "chat";

  // --- Лимиты бесплатных запросов (только для новых версий клиента) ---
  let quota = null;
  if (quotaKind) {
    quota = await consumeQuota(uid, quotaKind);
    if (!quota.allowed) throw new HttpsError("resource-exhausted", "QUOTA_EXCEEDED");
  }

  try {
    // --- Вложения ---
    let imagesBase64 = Array.isArray(data.imagesBase64) ? data.imagesBase64.filter((s) => typeof s === "string").slice(0, 5) : [];
    if (Array.isArray(data.imagePaths) && data.imagePaths.length) {
      imagesBase64 = await Promise.all(data.imagePaths.slice(0, 5).map((p) => loadStorageBase64(uid, p, 8 * 1024 * 1024)));
    }
    let pdfBase64 = typeof data.pdfBase64 === "string" ? data.pdfBase64 : null;
    if (typeof data.pdfPath === "string") pdfBase64 = await loadStorageBase64(uid, data.pdfPath, 10 * 1024 * 1024);
    if (imagesBase64.some((b) => b.length > 12 * 1024 * 1024) || (pdfBase64 && pdfBase64.length > 14 * 1024 * 1024)) {
      throw new HttpsError("invalid-argument", "Файл слишком большой.");
    }

    const hasFiles = imagesBase64.length > 0 || !!pdfBase64;
    const model = getGenAI().getGenerativeModel({
      model: geminiModel(),
      systemInstruction: `${EVA_SYSTEM_PROMPT}${mode === "meal_plan" ? MEAL_PLAN_RULES : ""}\n\nДОСЬЕ ПОЛЬЗОВАТЕЛЯ (ТЕКУЩИЙ КОНТЕКСТ):\n${userContext || "(Профиль пока не заполнен)"}`,
      // Размышления перед ответом сильно увеличивают ожидание. Для переписки и меню
      // они не нужны, для фото и анализов оставляем немного.
      generationConfig: genConfig({ temperature: hasFiles ? 0.1 : 0.4, think: hasFiles ? "low" : "off" }),
    });

    const userPrompt = prompt || (hasFiles ? "Посмотри файлы" : "Привет!");
    let result;
    if (pdfBase64) {
      result = await generateWithRetry(() => model.generateContent([userPrompt, { inlineData: { data: pdfBase64, mimeType: "application/pdf" } }]));
    } else if (imagesBase64.length > 0) {
      const parts = imagesBase64.map((b) => ({ inlineData: { data: b, mimeType: "image/jpeg" } }));
      result = await generateWithRetry(() => model.generateContent([userPrompt, ...parts]));
    } else {
      const history = data.serverHistory === true && botType ? await loadServerHistory(uid, botType) : data.history;
      const chat = model.startChat({ history: cleanHistory(history) });
      result = await generateWithRetry(() => chat.sendMessage(userPrompt));
    }

    const text = (result && result.response && result.response.text()) || "";
    if (!text.trim()) throw new Error("EMPTY_RESPONSE");

    if (saveReply) {
      const ref = await db.collection("users").doc(uid).collection(`ai_chats_${botType}`).add({
        text,
        role: "ai",
        timestamp: FieldValue.serverTimestamp(),
        isActionCompleted: false,
      });
      return { text, saved: true, messageId: ref.id, serverVersion: 2 };
    }
    return { text, serverVersion: 2 };
  } catch (error) {
    console.error("[askDietitian]", uid, error && error.message);
    await refundQuota(uid, quota);
    if (error instanceof HttpsError) throw error;
    if (saveReply) {
      // Пользователь мог закрыть экран — оставим понятное сообщение в чате.
      const fallback = "Ой, у меня не получилось ответить прямо сейчас 😔 Попробуй отправить сообщение ещё раз через минутку.";
      await db.collection("users").doc(uid).collection(`ai_chats_${botType}`).add({
        text: fallback, role: "ai", isError: true, timestamp: FieldValue.serverTimestamp(), isActionCompleted: true,
      }).catch(() => null);
    }
    throw new HttpsError("unavailable", "Ева временно недоступна. Попробуйте ещё раз.");
  }
});

// ==========================================
// 6. ИТОГИ НЕДЕЛИ ОТ ЕВЫ (новая функция)
// ==========================================
function dateId(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function isoWeekId(d) {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((date - yearStart) / 86400000) + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

exports.weeklyInsights = onCall({ maxInstances: 10, timeoutSeconds: 90 }, async (request) => {
  const uid = requireAuth(request);
  const force = request.data && request.data.force === true;
  const tzOffsetMin = toInt(request.data && request.data.tzOffsetMinutes, 180);
  const now = new Date(Date.now() + tzOffsetMin * 60000); // «локальное» время пользователя
  const weekId = isoWeekId(now);
  const cacheRef = db.collection("users").doc(uid).collection("insights").doc(weekId);

  const userSnap = await db.collection("users").doc(uid).get();
  const user = userSnap.exists ? userSnap.data() : {};

  if (!force || !isProActive(user)) {
    const cached = await cacheRef.get();
    if (cached.exists && cached.data().ai) {
      const c = cached.data();
      return { weekId, stats: c.stats || null, ai: c.ai, cached: true };
    }
  }

  const days = [];
  for (let i = 6; i >= 0; i--) days.push(dateId(new Date(now.getTime() - i * 86400000)));

  const [mealsSnaps, logsSnaps, goalSnap] = await Promise.all([
    db.getAll(...days.map((id) => db.collection("users").doc(uid).collection("meals").doc(id))),
    db.getAll(...days.map((id) => db.collection("users").doc(uid).collection("cycle_logs").doc(id))),
    db.collection("users").doc(uid).collection("nutrition_goal").doc("current").get(),
  ]);

  const goal = goalSnap.exists ? goalSnap.data() : {};
  const perDay = days.map((id, i) => {
    const m = mealsSnaps[i].exists ? mealsSnaps[i].data() : {};
    const l = logsSnaps[i].exists ? logsSnaps[i].data() : {};
    const items = Array.isArray(m.items) ? m.items : [];
    const sum = (k) => items.reduce((a, it) => a + toInt(it && it[k]), 0);
    return {
      date: id,
      calories: sum("calories"),
      protein: sum("protein"),
      fat: sum("fat"),
      carbs: sum("carbs"),
      fiber: sum("fiber"),
      meals: items.length,
      water: toInt(m.water_glasses),
      moods: Array.isArray(l.moods) ? l.moods : (l.mood ? [l.mood] : []),
      symptoms: l.symptoms && typeof l.symptoms === "object" ? Object.keys(l.symptoms) : [],
      sleep: l.sleep || null,
    };
  });

  const logged = perDay.filter((d) => d.meals > 0);
  const avg = (k) => logged.length ? Math.round(logged.reduce((a, d) => a + d[k], 0) / logged.length) : 0;
  const count = (arr) => arr.reduce((acc, x) => { acc[x] = (acc[x] || 0) + 1; return acc; }, {});
  const top = (obj) => Object.entries(obj).sort((a, b) => b[1] - a[1]).slice(0, 3).map((e) => e[0]);

  const stats = {
    daysLogged: logged.length,
    avgCalories: avg("calories"),
    avgProtein: avg("protein"),
    avgFiber: avg("fiber"),
    avgWater: Math.round(perDay.reduce((a, d) => a + d.water, 0) / 7 * 10) / 10,
    targetCalories: toInt(goal.calories),
    targetProtein: toInt(goal.protein),
    topMoods: top(count(perDay.flatMap((d) => d.moods))),
    topSymptoms: top(count(perDay.flatMap((d) => d.symptoms))),
    days: perDay.map((d) => ({ date: d.date, calories: d.calories, water: d.water, meals: d.meals })),
  };

  let ai = null;
  try {
    const model = getGenAI().getGenerativeModel({
      model: geminiModel(),
      // Как было: у 2.5 Flash размышления по умолчанию включены — оставляем «немного».
      generationConfig: genConfig({ temperature: 0.6, think: "low", json: true }),
    });
    const prompt = `Ты — Ева, тёплая ИИ-подруга и нутрициолог. Подведи итоги недели пользователя (${user.name || "подруга"}).
Цель: ${user.goal || user.goals || "не указана"}. Беременность: ${user.isPregnant ? "да" : "нет"}.
Данные за 7 дней (JSON): ${JSON.stringify(stats)}
Верни СТРОГО JSON без markdown:
{"headline": "короткий заголовок до 40 символов", "summary": "2-3 тёплых предложения без осуждения", "wins": ["2-3 конкретных достижения"], "tips": ["ровно 3 конкретных совета на следующую неделю, с продуктами из обычного супермаркета"], "score": число 1-10 — оценка баланса недели}
Если данных мало — мягко подбодри начать вести дневник. Не ставь диагнозов.`;
    const res = await generateWithRetry(() => model.generateContent(prompt));
    const raw = res.response.text().replace(/```json|```/g, "").trim();
    ai = JSON.parse(raw);
  } catch (e) {
    console.error("[weeklyInsights] AI failed", e && e.message);
  }

  const payload = { weekId, stats, ai, createdAt: FieldValue.serverTimestamp() };
  if (ai) await cacheRef.set(payload).catch(() => null);
  return { weekId, stats, ai, cached: false };
});

// ==========================================
// 7. ПОКУПКИ И ПРОМОКОДЫ
// ==========================================
const PRODUCTS = {
  "eva_sub_1_month": { type: "pro", days: 30 },
  "eva_sub_1_month_promo": { type: "pro", days: 30 },
  "eva_sub_1_year": { type: "pro", days: 365 },
  "eva_sub_1_year_promo": { type: "pro", days: 365 },
  "specialist_chat_monthly": { type: "specialist", days: 30 },
};

exports.verifyRuStorePurchase = onCall(async (request) => {
  const uid = requireAuth(request);
  const { purchaseToken, productId } = request.data || {};
  const product = PRODUCTS[productId];
  if (!product) throw new HttpsError("invalid-argument", "Неизвестный продукт.");
  if (typeof purchaseToken !== "string" || purchaseToken.length < 8 || purchaseToken.length > 200) {
    throw new HttpsError("invalid-argument", "Некорректный purchaseToken.");
  }

  // ВНИМАНИЕ: API RuStore недоступно из-за рубежа (Cloud Functions работают в США),
  // поэтому полноценная серверная проверка чека требует прокси в РФ
  // (например, Yandex Cloud Function). До этого момента защищаемся так:
  // 1) только авторизованные пользователи; 2) только известные продукты;
  // 3) одна покупка (purchaseId) = один аккаунт и одно применение.
  const purchaseRef = db.collection("purchases").doc(purchaseToken.replace(/[^A-Za-z0-9_-]/g, "_"));
  const userRef = db.collection("users").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const [pSnap, uSnap] = await Promise.all([tx.get(purchaseRef), tx.get(userRef)]);
      const user = uSnap.exists ? uSnap.data() : {};
      if (pSnap.exists) {
        const p = pSnap.data();
        if (p.uid !== uid) throw new HttpsError("permission-denied", "Покупка привязана к другому аккаунту.");
        // Продление подписки: та же покупка может продлить доступ не чаще одного раза за период.
        const lastTs = p.lastExtendedAt || p.createdAt;
        const last = lastTs && lastTs.toDate ? lastTs.toDate() : new Date(0);
        const minGapMs = Math.max(product.days - 3, 1) * 86400000;
        if (Date.now() - last.getTime() < minGapMs) return { success: true, alreadyApplied: true };
        tx.update(purchaseRef, { lastExtendedAt: FieldValue.serverTimestamp(), renewals: FieldValue.increment(1) });
      } else {
        tx.set(purchaseRef, { uid, productId, createdAt: FieldValue.serverTimestamp(), lastExtendedAt: FieldValue.serverTimestamp(), verified: false });
      }
      if (product.type === "specialist") {
        const cur = user.specialistUntil && user.specialistUntil.toDate ? user.specialistUntil.toDate() : new Date();
        const base = cur > new Date() ? cur : new Date();
        const until = new Date(base.getTime() + product.days * 86400000);
        tx.set(userRef, { hasSpecialistAccess: true, specialistUntil: Timestamp.fromDate(until) }, { merge: true });
      } else {
        const cur = user.proUntil && user.proUntil.toDate ? user.proUntil.toDate() : new Date();
        const base = cur > new Date() ? cur : new Date();
        const until = new Date(base.getTime() + product.days * 86400000);
        tx.set(userRef, { isPro: true, proUntil: Timestamp.fromDate(until) }, { merge: true });
      }
      return { success: true };
    });
    return { ...result, message: product.type === "specialist" ? "Доступ к специалисту открыт" : "Подписка успешно активирована" };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("🚨 verifyRuStorePurchase:", error);
    throw new HttpsError("internal", "Ошибка активации подписки");
  }
});

/** Промокоды проверяются на сервере (раньше START3 выдавал Premium прямо с клиента). */
exports.redeemPromo = onCall(async (request) => {
  const uid = requireAuth(request);
  const code = String((request.data && request.data.code) || "").trim().toUpperCase();
  if (!code || code.length > 40) throw new HttpsError("invalid-argument", "Введите промокод.");

  // Встроенные коды
  const builtIn = {
    START3: { type: "trial", days: 3 },
    SALE50: { type: "discount", percent: 50 },
    SALE50EVA: { type: "discount", percent: 50 },
  };
  let promo = builtIn[code] || null;
  if (!promo) {
    const snap = await db.collection("promocodes").where("code", "==", code).limit(1).get();
    if (!snap.empty) {
      const p = snap.docs[0].data();
      if (p.isActive === true) {
        promo = toInt(p.days) > 0 ? { type: "trial", days: toInt(p.days) } : { type: "discount", percent: toInt(p.discountPercent, 50) };
      }
    }
  }
  if (!promo) throw new HttpsError("not-found", "Неверный промокод");
  if (promo.type === "discount") return { type: "discount", percent: promo.percent, code: code === "SALE50EVA" ? "SALE50" : code };

  const userRef = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const user = snap.exists ? snap.data() : {};
    const used = Array.isArray(user.usedPromoCodes) ? user.usedPromoCodes : [];
    if (used.includes(code)) throw new HttpsError("already-exists", "Вы уже использовали этот промокод");
    const cur = user.proUntil && user.proUntil.toDate ? user.proUntil.toDate() : new Date();
    const base = isProActive(user) && cur > new Date() ? cur : new Date();
    const until = new Date(base.getTime() + promo.days * 86400000);
    tx.set(userRef, { isPro: true, proUntil: Timestamp.fromDate(until), usedPromoCodes: FieldValue.arrayUnion(code) }, { merge: true });
    return { type: "trial", days: promo.days, proUntil: until.getTime() };
  });
});


// ==========================================
// 9. СТАТИСТИКА ДЛЯ ВЛАДЕЛЬЦА (экран «Статистика приложения»)
// ==========================================
// Активность берётся из Firebase Auth: lastRefreshTime обновляется, пока
// приложение открыто (токен продлевается примерно раз в час), поэтому
// DAU/WAU/MAU считаются для всех версий приложения, включая старые.
// История по дням копится в admin_stats_daily (клиентам закрыта правилами).
const { getAuth } = require("firebase-admin/auth");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const OWNER_EMAILS = ["a.eduardmail@gmail.com"];
const MSK_OFFSET_MS = 3 * 3600000;
const DAY_MS = 86400000;

function canSeeStats(request) {
  if (!request.auth) return false;
  if (request.auth.uid === SUPPORT_ADMIN_UID) return true;
  const t = request.auth.token || {};
  const email = typeof t.email === "string" ? t.email.toLowerCase() : "";
  return OWNER_EMAILS.includes(email) && t.email_verified === true;
}

function mskDateKey(ms) {
  return new Date(ms + MSK_OFFSET_MS).toISOString().slice(0, 10);
}

async function safeCount(query) {
  try {
    const snap = await query.count().get();
    return snap.data().count;
  } catch (e) {
    console.warn("[adminStats] count:", e && e.message);
    return null;
  }
}

async function computeStats() {
  const now = Date.now();
  const startTodayMsk = Math.floor((now + MSK_OFFSET_MS) / DAY_MS) * DAY_MS - MSK_OFFSET_MS;

  // --- Пользователи и активность (Firebase Auth) ---
  let total = 0, dau = 0, wau = 0, mau = 0, newToday = 0, new7 = 0, new30 = 0;
  const regByDay = {};
  let pageToken;
  do {
    const res = await getAuth().listUsers(1000, pageToken);
    for (const u of res.users) {
      if (u.disabled) continue;
      total++;
      const created = Date.parse(u.metadata.creationTime || "") || 0;
      const lastSeen = Math.max(
        Date.parse(u.metadata.lastRefreshTime || "") || 0,
        Date.parse(u.metadata.lastSignInTime || "") || 0,
        created,
      );
      const idle = now - lastSeen;
      if (idle < DAY_MS) dau++;
      if (idle < 7 * DAY_MS) wau++;
      if (idle < 30 * DAY_MS) mau++;
      if (created >= startTodayMsk) newToday++;
      if (now - created < 7 * DAY_MS) new7++;
      if (now - created < 30 * DAY_MS) {
        new30++;
        const k = mskDateKey(created);
        regByDay[k] = (regByDay[k] || 0) + 1;
      }
    }
    pageToken = res.pageToken;
  } while (pageToken);

  const registrations = [];
  for (let i = 29; i >= 0; i--) {
    const k = mskDateKey(now - i * DAY_MS);
    registrations.push({ date: k, count: regByDay[k] || 0 });
  }

  // --- Путь до оплаты (Firestore) ---
  const users = db.collection("users");
  const [profiles, onboarded, usedEva, evaLimit, usedScan, scanLimit, trialStart3] = await Promise.all([
    safeCount(users),
    safeCount(users.where("isOnboardingCompleted", "==", true)),
    safeCount(users.where("free_messages_left", "<", FREE_LIMITS.message)),
    safeCount(users.where("free_messages_left", "==", 0)),
    safeCount(users.where("free_scans_left", "<", FREE_LIMITS.scan)),
    safeCount(users.where("free_scans_left", "==", 0)),
    safeCount(users.where("usedPromoCodes", "array-contains", "START3")),
  ]);

  let premiumActive = 0, premiumEver = 0;
  try {
    const pro = await users.where("isPro", "==", true).select("isPro", "proUntil").get();
    premiumEver = pro.size;
    pro.forEach((d) => { if (isProActive(d.data())) premiumActive++; });
  } catch (e) {
    console.warn("[adminStats] premium:", e && e.message);
  }

  let purchasesTotal = null, purchases30 = null;
  const purchasesByProduct = {};
  try {
    purchasesTotal = await safeCount(db.collection("purchases"));
    const p30 = await db.collection("purchases").where("createdAt", ">=", Timestamp.fromMillis(now - 30 * DAY_MS)).get();
    purchases30 = p30.size;
    p30.forEach((d) => {
      const id = String(d.data().productId || "unknown");
      purchasesByProduct[id] = (purchasesByProduct[id] || 0) + 1;
    });
  } catch (e) {
    console.warn("[adminStats] purchases:", e && e.message);
  }

  return {
    generatedAt: now,
    users: { total, dau, wau, mau, newToday, new7, new30, profiles },
    funnel: { registered: total, onboarded, usedEva, evaLimit, usedScan, scanLimit, trialStart3, premiumEver, premiumActive },
    purchases: { total: purchasesTotal, last30: purchases30, byProduct: purchasesByProduct },
    registrations,
  };
}

async function saveDailySnapshot(stats) {
  const key = mskDateKey(stats.generatedAt);
  await db.collection("admin_stats_daily").doc(key).set({
    date: key,
    dau: stats.users.dau,
    wau: stats.users.wau,
    mau: stats.users.mau,
    total: stats.users.total,
    newToday: stats.users.newToday,
    premiumActive: stats.funnel.premiumActive,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

exports.adminStats = onCall({ timeoutSeconds: 120, memory: "512MiB", maxInstances: 2 }, async (request) => {
  requireAuth(request);
  if (!canSeeStats(request)) throw new HttpsError("permission-denied", "Нет доступа к статистике.");
  const stats = await computeStats();
  await saveDailySnapshot(stats).catch((e) => console.warn("[adminStats] snapshot:", e && e.message));
  const hist = await db.collection("admin_stats_daily").orderBy("date", "desc").limit(60).get();
  const history = hist.docs.map((d) => {
    const x = d.data();
    return { date: x.date, dau: x.dau || 0, wau: x.wau || 0, mau: x.mau || 0, total: x.total || 0, newToday: x.newToday || 0 };
  }).reverse();
  return { ...stats, history };
});

/** Каждый день в 23:55 по Москве сохраняем снимок — из них строится график активности. */
exports.dailyStatsSnapshot = onSchedule({ schedule: "55 23 * * *", timeZone: "Europe/Moscow", timeoutSeconds: 300, memory: "512MiB" }, async () => {
  const stats = await computeStats();
  await saveDailySnapshot(stats);
});

// ==========================================
// 10. ЕВА НАЧИНАЕТ РАЗГОВОР ПЕРВОЙ
// ==========================================
// • evaGreetOnOnboarding — как только пользователь прошёл анкету, Ева пишет
//   персональное первое сообщение (имя, цель, фаза цикла) с кнопками-ответами.
// • evaNudge — если за ~сутки после анкеты пользователь так и не написал Еве,
//   Ева пишет ещё раз и присылает пуш (днём по Москве, один раз).
// • processWelcomeQueue — приветствие от службы заботы приходит через 30 минут
//   после регистрации, а не в момент регистрации (см. sendWelcomeMessage).

const EVA_CHAT = "ai_chats_dietitian";
const PHASE_NAMES = {
  menstruation: "менструация",
  follicular: "фолликулярная фаза",
  ovulation: "овуляция",
  luteal: "лютеиновая фаза",
};

function tsToMs(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  const n = Date.parse(v);
  return Number.isFinite(n) ? n : 0;
}

/** Коротко о состоянии пользователя для первого сообщения Евы. */
function userSnapshotForEva(data, now = Date.now()) {
  const d = data || {};
  const name = String(d.name || "").trim().split(/\s+/)[0] || "";
  const goal = String(d.goal || "").trim();
  const out = { name, goal, phaseKey: null, phase: null, cycleDay: null, pregnancyWeek: null };
  if (d.isPregnant === true || d.appMode === "pregnancy") {
    const start = tsToMs(d.pregnancyStartDate);
    if (start) out.pregnancyWeek = Math.max(1, Math.min(42, Math.floor((now - start) / (7 * DAY_MS)) + 1));
    return out;
  }
  const start = tsToMs(d.lastPeriodStartDate);
  if (!start) return out;
  const len = Math.min(45, Math.max(20, toInt(d.cycleLength, 28)));
  const period = Math.min(10, Math.max(2, toInt(d.periodDuration, 5)));
  const diff = Math.floor((now - start) / DAY_MS);
  if (diff < 0) return out;
  const day = (diff % len) + 1;
  const ov = Math.max(period + 2, len - 14);
  let key = "luteal";
  if (day <= period) key = "menstruation";
  else if (day < ov - 1) key = "follicular";
  else if (day <= ov + 1) key = "ovulation";
  out.cycleDay = day;
  out.phaseKey = key;
  out.phase = PHASE_NAMES[key];
  return out;
}

function fallbackGreeting(s) {
  const hi = s.name ? `Привет, ${s.name}! 🌸` : "Привет! 🌸";
  let about = "Я посмотрела твою анкету и уже рассчитала твою норму на день.";
  if (s.pregnancyWeek) about = `Я посмотрела твою анкету: у тебя ${s.pregnancyWeek}-я неделя — буду подсказывать питание именно под этот срок.`;
  else if (s.phase) about = `Я посмотрела твою анкету: сейчас у тебя ${s.phase}, ${s.cycleDay}-й день цикла — в это время организму особенно важно правильное питание.`;
  return {
    text: `${hi} Я Ева — твой личный нутрициолог и подруга.\n\n${about}\n\nМогу прямо сейчас подсказать, что приготовить сегодня, посчитать калории по фото тарелки или объяснить анализы простым языком. С чего начнём?`,
    suggestions: [
      s.phase ? "Что мне есть в эту фазу?" : "Что мне есть сегодня?",
      "Составь меню на день",
      "Как ты считаешь калории по фото?",
    ],
  };
}

function cleanSuggestions(list) {
  return (Array.isArray(list) ? list : [])
    .map((x) => String(x || "").replace(/\s+/g, " ").trim())
    .filter((x) => x.length >= 3 && x.length <= 48)
    .slice(0, 3);
}

async function generateGreeting(s) {
  const facts = [
    s.name ? `Имя: ${s.name}` : "Имя не указано",
    s.goal ? `Цель: ${s.goal}` : null,
    s.pregnancyWeek ? `Беременность, ${s.pregnancyWeek}-я неделя` : null,
    s.phase ? `Сейчас ${s.phase}, ${s.cycleDay}-й день цикла` : null,
  ].filter(Boolean).join("\n");
  const model = getGenAI().getGenerativeModel({
    model: geminiModel(),
    systemInstruction: EVA_SYSTEM_PROMPT,
    generationConfig: genConfig({ temperature: 0.7, think: "off", json: true }),
  });
  const prompt = `Пользователь только что зарегистрировался и заполнил анкету. Напиши ПЕРВОЕ сообщение от себя — ты начинаешь разговор.
Данные анкеты:
${facts}

Требования к тексту:
- поздоровайся по имени и коротко представься (одно предложение);
- покажи, что ты уже знаешь её анкету: упомяни цель и фазу цикла (или срок беременности) и дай ОДИН конкретный полезный совет на сегодня именно под это;
- одной фразой скажи, что ещё умеешь: калории по фото тарелки, меню, разбор анализов;
- закончи простым вопросом, на который легко ответить;
- 4–6 коротких предложений, тепло, на «ты», 1–2 эмодзи, без markdown-заголовков, без JSON-блоков внутри текста.
Также придумай 3 коротких варианта ответа от лица пользователя (до 40 символов каждый), которые продолжают разговор.
Ответ строго JSON: {"text": "...", "suggestions": ["...", "...", "..."]}`;
  const result = await generateWithRetry(() => model.generateContent(prompt));
  const raw = (result && result.response && result.response.text()) || "";
  const parsed = JSON.parse(raw.replace(/^```(?:json)?\s*|\s*```$/g, ""));
  const text = String(parsed.text || "").trim();
  if (text.length < 40 || text.length > 1500) throw new Error("BAD_GREETING");
  const suggestions = cleanSuggestions(parsed.suggestions);
  return { text, suggestions: suggestions.length === 3 ? suggestions : fallbackGreeting(s).suggestions };
}

exports.evaGreetOnOnboarding = onDocumentWritten({ document: "users/{uid}", timeoutSeconds: 60, memory: "256MiB" }, async (event) => {
  const before = event.data && event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  // Только переход «анкета не пройдена» → «пройдена» (новые регистрации).
  if (!before || !after || before.isOnboardingCompleted !== false || after.isOnboardingCompleted !== true) return;
  const uid = event.params.uid;
  const ref = db.collection("users").doc(uid).collection(EVA_CHAT).doc("eva_greeting_v1");
  const s = userSnapshotForEva(after);
  let msg;
  try {
    msg = await generateGreeting(s);
  } catch (e) {
    console.warn("[evaGreetOnOnboarding] fallback:", e && e.message);
    msg = fallbackGreeting(s);
  }
  try {
    await ref.create({
      text: msg.text,
      role: "ai",
      kind: "greeting",
      suggestions: msg.suggestions,
      timestamp: FieldValue.serverTimestamp(),
      isActionCompleted: true,
    });
  } catch (e) {
    if (e.code !== 6) console.error("[evaGreetOnOnboarding]", uid, e.message); // 6 = уже есть
  }
});

function nudgeText(s) {
  const hi = s.name ? `${s.name}, ` : "";
  if (s.pregnancyWeek) {
    return {
      push: `${hi}я подобрала, что полезно есть на ${s.pregnancyWeek}-й неделе 🤍 Посмотришь?`,
      chat: `${s.name ? s.name + ", привет" : "Привет"}! 🤍 У тебя сейчас ${s.pregnancyWeek}-я неделя — это время, когда особенно важны белок, железо и фолиевая кислота.\n\nХочешь, составлю простое меню на сегодня из обычных продуктов? Или пришли фото своей тарелки — посчитаю, всего ли хватает.`,
      suggestions: ["Да, составь меню", "Что важно на моём сроке?", "Посчитать еду по фото"],
    };
  }
  if (s.phase) {
    return {
      push: `${hi}у тебя сейчас ${s.phase} 🌿 Подскажу, что лучше есть сегодня — загляни!`,
      chat: `${s.name ? s.name + ", привет" : "Привет"}! 🌿 У тебя ${s.cycleDay}-й день цикла — ${s.phase}. В эти дни питание заметно влияет на энергию, настроение и аппетит.\n\nПодсказать, что лучше есть сегодня? Могу сразу составить меню на твою норму.`,
      suggestions: ["Да, что мне есть сегодня?", "Составь меню на день", "Почему фаза важна?"],
    };
  }
  return {
    push: `${hi}я подготовила идеи, что приготовить сегодня под твою цель 🌸 Загляни!`,
    chat: `${s.name ? s.name + ", привет" : "Привет"}! 🌸 Я подготовила для тебя пару идей, что приготовить сегодня под твою цель${s.goal ? ` «${s.goal}»` : ""}.\n\nПоказать меню на день? А ещё можешь прислать фото тарелки — посчитаю калории за секунды.`,
    suggestions: ["Да, покажи меню", "Посчитать еду по фото", "Как ты можешь помочь?"],
  };
}

async function hasUserWrittenToEva(uid) {
  const snap = await db.collection("users").doc(uid).collection(EVA_CHAT).where("role", "==", "user").limit(1).get();
  return !snap.empty;
}

exports.evaNudge = onSchedule({ schedule: "20 * * * *", timeZone: "Europe/Moscow", timeoutSeconds: 300, memory: "256MiB" }, async () => {
  const now = Date.now();
  const mskHour = new Date(now + MSK_OFFSET_MS).getUTCHours();
  if (mskHour < 10 || mskHour > 20) return; // не будим ночью
  const snap = await db.collection("users")
    .where("joinDate", ">=", Timestamp.fromMillis(now - 72 * 3600000))
    .where("joinDate", "<=", Timestamp.fromMillis(now - 20 * 3600000))
    .get();
  let sent = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.evaNudgeSent || d.isOnboardingCompleted !== true || isProActive(d)) continue;
    try {
      if (await hasUserWrittenToEva(doc.id)) {
        await doc.ref.set({ evaNudgeSent: "skipped" }, { merge: true });
        continue;
      }
      const s = userSnapshotForEva(d, now);
      const t = nudgeText(s);
      await doc.ref.collection(EVA_CHAT).doc("eva_nudge_v1").set({
        text: t.chat,
        role: "ai",
        kind: "nudge",
        suggestions: t.suggestions,
        timestamp: FieldValue.serverTimestamp(),
        isActionCompleted: true,
      });
      await doc.ref.set({ evaNudgeSent: true }, { merge: true });
      await sendPush(doc.id, "Ева", t.push, { type: "eva", botType: "dietitian" });
      sent++;
    } catch (e) {
      console.error("[evaNudge]", doc.id, e && e.message);
    }
  }
  if (sent) console.log(`[evaNudge] sent ${sent}`);
});

exports.processWelcomeQueue = onSchedule({ schedule: "every 5 minutes", timeoutSeconds: 120, memory: "256MiB" }, async () => {
  const due = await db.collection("welcome_queue").where("dueAt", "<=", Timestamp.now()).limit(100).get();
  for (const q of due.docs) {
    const uid = q.id;
    try {
      const user = await db.collection("users").doc(uid).get();
      if (user.exists) await createWelcomeMessage(uid);
      await q.ref.delete();
    } catch (e) {
      console.error("[processWelcomeQueue]", uid, e && e.message);
    }
  }
});

// ==========================================
// ВРЕМЕННО: проверка моделей Gemini перед переходом с 2.5 Flash (до 01.12.2026).
// Работает, только если в .env задан AI_PROBE_TOKEN; запрос — с этим токеном в заголовке.
// Пользовательских данных не трогает: тестовые тексты, картинка с сайта и маленький PDF.
// После выбора модели — удалить функцию и токен.
// ==========================================
function tinyPdfBase64() {
  const text = "Blood test: Hemoglobin 112 g/L (ref 120-150). Ferritin 9 ng/mL (ref 15-150). Vitamin D 18 ng/mL (ref 30-100).";
  const stream = `BT /F1 10 Tf 40 760 Td (${text}) Tj ET`;
  const objs = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let pdf = "%PDF-1.4\n";
  const offsets = [];
  objs.forEach((o, i) => {
    offsets.push(pdf.length);
    pdf += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = pdf.length;
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offsets.map((o) => `${String(o).padStart(10, "0")} 00000 n \n`).join("")}`;
  pdf += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return Buffer.from(pdf, "latin1").toString("base64");
}

exports.aiProbe = onRequest({ timeoutSeconds: 300, memory: "512MiB", maxInstances: 1 }, async (req, res) => {
  const token = probeToken.value();
  if (!token || req.get("x-probe-token") !== token) {
    res.status(404).send("Not found");
    return;
  }
  const models = String(req.query.models || "gemini-2.5-flash").split(",").map((s) => s.trim()).filter(Boolean).slice(0, 6);
  const out = { listed: [], results: [] };

  try {
    const r = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", { headers: { "x-goog-api-key": geminiKey.value() } });
    const j = await r.json();
    out.listed = (j.models || [])
      .filter((m) => /flash/i.test(m.name) && (m.supportedGenerationMethods || []).includes("generateContent"))
      .map((m) => m.name.replace("models/", ""));
    if (j.error) out.listError = `${j.error.status}: ${j.error.message}`;
  } catch (e) {
    out.listError = String(e && e.message);
  }

  let imgB64 = null;
  try {
    const r = await fetch(String(req.query.img || "https://commons.wikimedia.org/wiki/Special:FilePath/Full_English_breakfast.jpg?width=800"), { headers: { "User-Agent": "MyEvaModelCheck/1.0 (https://my-eva.ru)" }, redirect: "follow" });
    if (!r.ok) throw new Error(`image HTTP ${r.status}`);
    out.imgType = r.headers.get("content-type");
    imgB64 = Buffer.from(await r.arrayBuffer()).toString("base64");
  } catch (e) {
    out.imgError = String(e && e.message);
  }
  const pdfB64 = tinyPdfBase64();

  for (const name of models) {
    const tests = [
      ["chat", async () => {
        const m = getGenAI().getGenerativeModel({ model: name, systemInstruction: EVA_SYSTEM_PROMPT, generationConfig: genConfig({ temperature: 0.4, think: "off" }, name) });
        const chat = m.startChat({ history: cleanHistory([
          { role: "user", text: "Привет! Я съела овсянку с бананом на завтрак." },
          { role: "ai", text: "Отличный завтрак! Овсянка с бананом даёт энергию надолго 💛" },
        ]) });
        return chat.sendMessage("Что я ела на завтрак и сколько там примерно калорий? Коротко.");
      }],
      ["json", async () => {
        const m = getGenAI().getGenerativeModel({ model: name, systemInstruction: EVA_SYSTEM_PROMPT, generationConfig: genConfig({ temperature: 0.7, think: "off", json: true }, name) });
        return m.generateContent('Верни строго JSON {"text":"приветствие в 2 предложения","suggestions":["...","...","..."]} для новой пользовательницы Анны с целью «похудеть».');
      }],
      ["image", async () => {
        if (!imgB64) throw new Error("no image");
        const m = getGenAI().getGenerativeModel({ model: name, systemInstruction: EVA_SYSTEM_PROMPT, generationConfig: genConfig({ temperature: 0.1, think: "low" }, name) });
        return m.generateContent(["Запиши, что я съела на фото.", { inlineData: { data: imgB64, mimeType: (out.imgType || "image/jpeg").split(";")[0] } }]);
      }],
      ["pdf", async () => {
        const m = getGenAI().getGenerativeModel({ model: name, systemInstruction: EVA_SYSTEM_PROMPT, generationConfig: genConfig({ temperature: 0.1, think: "low" }, name) });
        return m.generateContent(["Расшифруй мои анализы коротко.", { inlineData: { data: pdfB64, mimeType: "application/pdf" } }]);
      }],
    ];
    for (const [test, fn] of tests) {
      const t0 = Date.now();
      try {
        const r = await fn();
        const u = r.response.usageMetadata || {};
        const text = r.response.text() || "";
        out.results.push({ model: name, test, ok: !!text.trim(), ms: Date.now() - t0, in: u.promptTokenCount, out: u.candidatesTokenCount, think: u.thoughtsTokenCount, text: text.slice(0, 600) });
      } catch (e) {
        out.results.push({ model: name, test, ok: false, ms: Date.now() - t0, error: String(e && e.message).slice(0, 300) });
      }
    }
  }
  res.json(out);
});
