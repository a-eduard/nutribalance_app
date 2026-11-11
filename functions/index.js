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

const { onCall, HttpsError } = require("firebase-functions/v2/https");
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
// Модели. С 01.12.2026 gemini-2.5-flash выключается (редирект на 3.5-flash-lite) —
// поэтому переходим заранее. Переопределяются в functions/.env без правки кода:
//   GEMINI_TEXT_MODEL, GEMINI_VISION_MODEL, TEXT_PROVIDER=gemini|deepseek, DEEPSEEK_API_KEY, DEEPSEEK_MODEL
const TEXT_MODEL = process.env.GEMINI_TEXT_MODEL || process.env.GEMINI_MODEL || "gemini-3.5-flash-lite";
const VISION_MODEL = process.env.GEMINI_VISION_MODEL || process.env.GEMINI_MODEL_FILES || "gemini-3.5-flash-lite";
const TEXT_PROVIDER = process.env.TEXT_PROVIDER || "gemini";
const DEEPSEEK_MODEL = process.env.DEEPSEEK_MODEL || "deepseek-flash";

/**
 * generationConfig под модель: у Gemini 3.x — thinkingLevel и без temperature
 * (иначе HTTP 400 / параметр игнорируется), у 2.x — старый thinkingBudget.
 */
function genConfig(model, level = "minimal", extra = {}) {
  if (/^gemini-2/.test(model)) {
    const budget = { minimal: 0, low: 512, medium: 1024, high: 4096 }[level] || 0;
    return { ...extra, thinkingConfig: { thinkingBudget: budget } };
  }
  return { ...extra, thinkingConfig: { thinkingLevel: level } };
}

// Цены USD за 1 млн токенов: [вход, выход (вкл. «размышления»), кэшированный вход].
const AI_PRICES = {
  "gemini-3.5-flash-lite": [0.30, 2.50, 0.03],
  "gemini-2.5-flash": [0.30, 2.50, 0.03],
  "gemini-2.5-flash-lite": [0.10, 0.40, 0.01],
  "gemini-3.7-flash": [0.75, 3.75, 0.075],
  "gemini-3.8-flash": [0.75, 3.75, 0.075],
  "gemini-3.5-flash": [1.50, 9.00, 0.15],
  "deepseek-flash": [0.30, 1.20, 0.006],
};

/**
 * Учёт расходов на ИИ: ai_usage/{день МСК} → { [функция]: {calls, in, out, cached, usd}, total: {...} }.
 * Смотреть — экран «Статистика приложения». Ошибка учёта никогда не ломает ответ.
 */
async function trackUsage(feature, model, u) {
  try {
    if (!u) return;
    const tin = toInt(u.in), tout = toInt(u.out), cached = Math.min(toInt(u.cached), tin);
    const pr = AI_PRICES[model] || [1.5, 9, 0.15];
    const usd = ((tin - cached) * pr[0] + cached * pr[2] + tout * pr[1]) / 1e6;
    const inc = (v) => FieldValue.increment(v);
    const row = { calls: inc(1), in: inc(tin), out: inc(tout), cached: inc(cached), usd: inc(usd) };
    await db.collection("ai_usage").doc(mskDayKey()).set({ [feature]: row, total: row, models: { [model.replace(/\./g, "_")]: inc(usd) } }, { merge: true });
  } catch (e) {
    console.warn("[trackUsage]", feature, e && e.message);
  }
}

/** usageMetadata Gemini → {in, out, cached}. */
function geminiUsage(result) {
  const m = result && result.response && result.response.usageMetadata;
  if (!m) return null;
  return { in: m.promptTokenCount, out: toInt(m.candidatesTokenCount) + toInt(m.thoughtsTokenCount), cached: m.cachedContentTokenCount };
}

/** DeepSeek (OpenAI-совместимый API). Только текст. */
async function deepseekChat({ system, history, prompt, json = false, maxTokens = 1500 }) {
  const key = process.env.DEEPSEEK_API_KEY;
  if (!key) throw new Error("DEEPSEEK_API_KEY not set");
  const messages = [{ role: "system", content: system }];
  for (const h of history || []) messages.push({ role: h.role === "model" ? "assistant" : "user", content: h.parts[0].text });
  messages.push({ role: "user", content: prompt });
  const res = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${key}` },
    body: JSON.stringify({
      model: DEEPSEEK_MODEL, messages, temperature: 0.5, max_tokens: maxTokens,
      ...(json ? { response_format: { type: "json_object" } } : {}),
    }),
    signal: AbortSignal.timeout(60000),
  });
  if (!res.ok) throw new Error(`deepseek ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = await res.json();
  const text = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || "";
  const u = j.usage || {};
  return { text, usage: { in: u.prompt_tokens, out: u.completion_tokens, cached: u.prompt_cache_hit_tokens } };
}
const FREE_LIMITS = { message: 5, scan: 3 };
// Добросовестное использование PRO (в день, МСК): защищает от ухода в минус. См. Пользовательское соглашение, п. 4.4.
const PRO_DAILY_LIMITS = { message: 50, scan: 15 };
const PRO_LIMIT_TEXT = "Сегодня ты уже очень много общалась с Евой 💗 Дневной лимит обновится завтра в 00:00 по Москве.";

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
    const userSnap = await userRef.get();
    const ud = userSnap.exists ? userSnap.data() : {};
    if (ud.partnerUid) await unlinkPair(uid, ud.partnerUid).catch(() => null);
    if (ud.partnerOf) await unlinkPair(ud.partnerOf, uid).catch(() => null);
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
const WELCOME_TEXT = `Здравствуйте! 👋 Добро пожаловать в «Мою Еву»! Я Мария, служба заботы о пользователях.

Посмотрите короткий видео-обзор — за пару минут покажем, что умеет Ева: калории по фото, календарь цикла, косметолог, анализы и голосовые сообщения:
🎬 https://vkvideo.ru/video-237160300_456239022

Если что-то непонятно или чего-то не хватает — пишите сюда, я всегда на связи и с радостью помогу 💗

Подписывайтесь на нас — советы о питании и цикле, ролики с Евой и новости женского здоровья:
💙 ВКонтакте: https://vk.ru/myeva_app
✈️ Telegram: https://t.me/myeva_app`;

/**
 * Срабатывает один раз при создании аккаунта. Кладёт сообщение от аккаунта поддержки
 * в обычный чат с поддержкой; счётчик непрочитанных и пуш делает onNewChatMessage.
 * Фиксированный ID сообщения — повторный запуск не создаст дубль.
 */
/** Кладёт приветствие от службы заботы в чат с поддержкой (идемпотентно). */
async function createWelcomeMessage(uid) {
  const u = await db.collection("users").doc(uid).get();
  if (u.exists && u.data().appRole === "partner") return; // партнёру приветствие для девушек не шлём
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
- JSON log_food добавляй ТОЛЬКО когда пользователь сообщает, что УЖЕ съела что-то, или присылает фото своей еды. В меню, рецептах и советах «что съесть» log_food НЕ добавляй. В одном ответе — не больше одного JSON-блока.
- Анализы: объясни простым языком, дай общие рекомендации по питанию, напомни, что диагноз ставит врач.
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
const ANALYSES_RULES = `

ТЫ В ЧАТЕ «АНАЛИЗЫ И ЗДОРОВЬЕ». Здесь пользовательница присылает результаты анализов (PDF или фото бланка).
- Разбирай каждый показатель: что он значит, норма ли (с учётом пола и возраста из досье), что может влиять.
- Отклонения объясняй спокойно, без запугивания. Подскажи, что можно поправить питанием и образом жизни.
- Если отклонения существенные — мягко посоветуй обратиться к врачу и подскажи, к какому специалисту.
- Если она присылала анализы раньше (видно в истории) — сравни динамику.
- Никаких диагнозов и назначений лекарств. Здесь не добавляй JSON log_food.`;

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
    if (isProActive(data)) {
      const day = mskDayKey();
      const u = data.proUsage && data.proUsage.day === day ? data.proUsage : { day };
      const used = toInt(u[kind]);
      if (used >= (PRO_DAILY_LIMITS[kind] || 50)) return { allowed: false, pro: true, limit: true };
      tx.set(ref, { proUsage: { ...u, day, [kind]: used + 1 } }, { merge: true });
      return { allowed: true, pro: true };
    }
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

const BOT_TITLES = { dietitian: "Питание", cosmetologist: "Уход за кожей", analyses: "Анализы и здоровье" };

/**
 * «Ева помнит всё»: свежие сообщения из других её чатов, последний анализ кожи и сканы.
 * Добавляется к системной инструкции, чтобы чаты были раздельными, но Ева — одна.
 */
async function crossChatMemory(uid, botType) {
  const userRef = db.collection("users").doc(uid);
  const others = Object.keys(BOT_TITLES).filter((b) => b !== botType);
  const [chats, skin, scans, shelf] = await Promise.all([
    Promise.all(others.map((b) => userRef.collection(`ai_chats_${b}`).orderBy("timestamp", "desc").limit(4).get().catch(() => null))),
    userRef.collection("skin_checks").orderBy("at", "desc").limit(1).get().catch(() => null),
    userRef.collection("label_scans").orderBy("at", "desc").limit(3).get().catch(() => null),
    userRef.collection("cosmetics_shelf").limit(40).get().catch(() => null),
  ]);
  const lines = [];
  chats.forEach((snap, i) => {
    if (!snap || snap.empty) return;
    const msgs = snap.docs.reverse().map((d) => {
      const m = d.data();
      const t = String(m.text || "").replace(/```[\s\S]*?```/g, "").replace(/\s+/g, " ").trim().slice(0, 220);
      return t ? `  ${m.role === "ai" ? "Ева" : "Она"}: ${t}` : null;
    }).filter(Boolean);
    if (msgs.length) lines.push(`[Чат «${BOT_TITLES[others[i]]}»]`, ...msgs);
  });
  if (skin && !skin.empty) {
    const k = skin.docs[0].data();
    const when = tsToMs(k.at) ? new Date(tsToMs(k.at)).toISOString().slice(0, 10) : "";
    const concerns = (k.concerns || []).map((c) => `${c.name} (${c.zone}, ${c.level}/3)`).join("; ");
    lines.push(`[Анализ кожи по фото ${when}] тип: ${k.skinType || "?"}${k.sensitivity ? ", чувствительная" : ""}; ${concerns || "без выраженных проблем"}`);
  }
  if (scans && !scans.empty) {
    lines.push(`[Последние сканы этикеток] ${scans.docs.map((d) => `${d.data().productName} (${d.data().kind === "cosmetic" ? "косметика" : "продукт"}, ${d.data().score})`).join("; ")}`);
  }
  if (shelf && !shelf.empty) {
    // Полка косметики: что у неё реально есть дома. Косметологу — подробно, остальным — коротко.
    const items = shelf.docs.map((d) => {
      const x = d.data();
      const base = `${x.productName || "средство"}${x.productType ? ` (${x.productType})` : ""}`;
      if (botType !== "cosmetologist") return base;
      const good = (x.good || []).map((g) => g && g.name).filter(Boolean).slice(0, 4).join(", ");
      const watch = (x.watch || []).map((w) => w && w.name).filter(Boolean).slice(0, 3).join(", ");
      const skinFit = (x.skinTypes || []).slice(0, 4).join("/");
      return `${base}; активы: ${good || "—"}; осторожно: ${watch || "—"}; кому: ${skinFit || "—"}; беременность: ${x.pregnancy || "?"}`;
    });
    lines.push(`[Моя полка косметики — ${items.length} шт.]`, ...items.map((t) => `  • ${t}`));
  }
  if (!lines.length) return "";
  return `\n\nПАМЯТЬ ИЗ ДРУГИХ ЧАТОВ И ФУНКЦИЙ (это та же пользовательница; используй, если она ссылается на это или это помогает ответу, но не пересказывай без повода):\n${lines.join("\n")}`;
}

function cleanHistory(history) {
  const out = [];
  let expected = "user";
  for (const msg of (Array.isArray(history) ? history : []).slice(-10)) {
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
    if (!quota.allowed) throw quota.limit ? new HttpsError("failed-precondition", PRO_LIMIT_TEXT) : new HttpsError("resource-exhausted", "QUOTA_EXCEEDED");
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
    // Постоянная часть (инструкция) идёт первой — так срабатывает дешёвый кэш входа.
    const persona = botType === "cosmetologist" ? COSMETOLOGIST_PROMPT : botType === "analyses" ? EVA_SYSTEM_PROMPT + ANALYSES_RULES : EVA_SYSTEM_PROMPT;
    const memory = await crossChatMemory(uid, botType).catch(() => "");
    const system = `${persona}${mode === "meal_plan" ? MEAL_PLAN_RULES : ""}${NAME_RULE}\n\nДОСЬЕ ПОЛЬЗОВАТЕЛЯ (ТЕКУЩИЙ КОНТЕКСТ):\n${userContext || "(Профиль пока не заполнен)"}${memory}`;
    const modelName = hasFiles ? VISION_MODEL : TEXT_MODEL;
    const feature = hasFiles ? (pdfBase64 ? "chat_pdf" : "chat_photo") : (botType === "cosmetologist" ? "chat_cosmetologist" : "chat_text");
    const model = getGenAI().getGenerativeModel({
      model: modelName,
      systemInstruction: system,
      // Переписке «размышления» не нужны (быстрее и дешевле), фото и анализам — немного.
      generationConfig: genConfig(modelName, hasFiles ? "low" : "minimal"),
    });

    const userPrompt = prompt || (hasFiles ? "Посмотри файлы" : "Привет!");
    let text = "";
    if (pdfBase64) {
      const result = await generateWithRetry(() => model.generateContent([userPrompt, { inlineData: { data: pdfBase64, mimeType: "application/pdf" } }]));
      await trackUsage(feature, modelName, geminiUsage(result));
      text = (result && result.response && result.response.text()) || "";
    } else if (imagesBase64.length > 0) {
      const parts = imagesBase64.map((b) => ({ inlineData: { data: b, mimeType: "image/jpeg" } }));
      const result = await generateWithRetry(() => model.generateContent([userPrompt, ...parts]));
      await trackUsage(feature, modelName, geminiUsage(result));
      text = (result && result.response && result.response.text()) || "";
    } else {
      const rawHistory = data.serverHistory === true && botType ? await loadServerHistory(uid, botType) : data.history;
      const history = cleanHistory(rawHistory);
      if (TEXT_PROVIDER === "deepseek" && process.env.DEEPSEEK_API_KEY) {
        try {
          const ds = await deepseekChat({ system, history, prompt: userPrompt, maxTokens: 2600 }); // длинные разборы (полка, анализы) обрезались на 1500
          await trackUsage(`${feature}_ds`, DEEPSEEK_MODEL, ds.usage);
          text = ds.text;
        } catch (e) {
          console.warn("[askDietitian] deepseek → gemini fallback:", e && e.message);
          // Для экрана статистики: сколько раз DeepSeek не ответил и последняя причина.
          await db.collection("ai_usage").doc(mskDayKey()).set({
            errors: { deepseek: FieldValue.increment(1) },
            lastError: { deepseek: String((e && e.message) || e).slice(0, 300) },
          }, { merge: true }).catch(() => null);
        }
      }
      if (!text.trim()) {
        const chat = model.startChat({ history });
        const result = await generateWithRetry(() => chat.sendMessage(userPrompt));
        await trackUsage(feature, modelName, geminiUsage(result));
        text = (result && result.response && result.response.text()) || "";
      }
    }

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
      model: TEXT_MODEL,
      generationConfig: genConfig(TEXT_MODEL, "low", { responseMimeType: "application/json" }),
    });
    const prompt = `Ты — Ева, тёплая ИИ-подруга и нутрициолог. Подведи итоги недели пользователя (${user.name || "подруга"}).
Цель: ${user.goal || user.goals || "не указана"}. Беременность: ${user.isPregnant ? "да" : "нет"}.
Данные за 7 дней (JSON): ${JSON.stringify(stats)}
Верни СТРОГО JSON без markdown:
{"headline": "короткий заголовок до 40 символов", "summary": "2-3 тёплых предложения без осуждения", "wins": ["2-3 конкретных достижения"], "tips": ["ровно 3 конкретных совета на следующую неделю, с продуктами из обычного супермаркета"], "score": число 1-10 — оценка баланса недели}
Если данных мало — мягко подбодри начать вести дневник. Не ставь диагнозов.`;
    const res = await generateWithRetry(() => model.generateContent(prompt));
    await trackUsage("weekly_insights", TEXT_MODEL, geminiUsage(res));
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
  // С версии 2.0 — новые цены (449 / 2 990 ₽). Старые продукты остаются для старых версий приложения.
  "eva_pro_month": { type: "pro", days: 30 },
  "eva_pro_month_promo": { type: "pro", days: 30 },
  "eva_pro_year": { type: "pro", days: 365 },
  "eva_pro_year_promo": { type: "pro", days: 365 },
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
  // Код подруги (реферальная программа «Пригласи подругу»)
  if (!promo && /^EVA[A-Z2-9]{5}$/.test(code)) {
    const refSnap = await db.collection("referral_codes").doc(code).get();
    if (refSnap.exists) return applyReferral(uid, code, refSnap.data().uid);
  }
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

  // --- Расходы на ИИ (ai_usage, последние 7 дней МСК) ---
  const usdRub = Number(process.env.USD_RUB) || 100;
  const ai = { usdRub, today: 0, week: 0, callsWeek: 0, features: {}, days: [], textProvider: TEXT_PROVIDER, deepseekKey: !!process.env.DEEPSEEK_API_KEY, deepseekModel: DEEPSEEK_MODEL, textModel: TEXT_MODEL, visionModel: VISION_MODEL };
  try {
    const keys = [];
    for (let i = 6; i >= 0; i--) keys.push(mskDayKey(now - i * DAY_MS));
    const snaps = await Promise.all(keys.map((k) => db.collection("ai_usage").doc(k).get()));
    snaps.forEach((snap, idx) => {
      const d = snap.exists ? snap.data() : {};
      const t = d.total || {};
      const rub = (Number(t.usd) || 0) * usdRub;
      ai.days.push({ date: keys[idx], rub: Math.round(rub * 100) / 100, calls: toInt(t.calls) });
      ai.week += rub;
      ai.callsWeek += toInt(t.calls);
      if (idx === snaps.length - 1) ai.today = rub;
      if (d.errors && d.errors.deepseek) ai.deepseekErrors = (ai.deepseekErrors || 0) + toInt(d.errors.deepseek);
      if (d.lastError && d.lastError.deepseek) ai.deepseekLastError = d.lastError.deepseek;
      for (const [f, v] of Object.entries(d)) {
        if (f === "total" || f === "models" || f === "errors" || f === "lastError" || !v || typeof v !== "object") continue;
        const acc = ai.features[f] || (ai.features[f] = { calls: 0, rub: 0, in: 0, out: 0 });
        acc.calls += toInt(v.calls);
        acc.rub += (Number(v.usd) || 0) * usdRub;
        acc.in += toInt(v.in);
        acc.out += toInt(v.out);
      }
    });
    ai.today = Math.round(ai.today * 100) / 100;
    ai.week = Math.round(ai.week * 100) / 100;
    for (const f of Object.values(ai.features)) f.rub = Math.round(f.rub * 100) / 100;
  } catch (e) {
    console.warn("[adminStats] ai:", e && e.message);
  }

  // --- Кто сейчас с Premium и откуда ---
  const premiumUsers = [];
  try {
    const [proSnap, purSnap] = await Promise.all([
      db.collection("users").where("isPro", "==", true).get(),
      db.collection("purchases").get(),
    ]);
    const bought = {};
    purSnap.forEach((d) => {
      const p = d.data();
      if (p.uid) (bought[p.uid] = bought[p.uid] || []).push(String(p.productId || "?") + (p.verified ? "" : " (не проверена RuStore)"));
    });
    proSnap.forEach((d) => {
      const u = d.data();
      if (!isProActive(u)) return;
      const promos = Array.isArray(u.usedPromoCodes) ? u.usedPromoCodes : [];
      const source = bought[d.id] ? `покупка: ${bought[d.id].join(", ")}`
        : promos.length ? `промокод: ${promos.join(", ")}`
          : u.referredBy || toInt(u.referralRewards) > 0 ? "пригласи подругу"
            : "выдан вручную / пробный";
      premiumUsers.push({
        name: String(u.name || "—").slice(0, 40),
        email: String(u.email || "").slice(0, 60),
        until: tsToMs(u.proUntil),
        source,
        owner: d.id === SUPPORT_ADMIN_UID,
      });
    });
    premiumUsers.sort((a, b) => b.until - a.until);
  } catch (e) {
    console.warn("[adminStats] premiumUsers:", e && e.message);
  }

  return {
    generatedAt: now,
    ai,
    premiumUsers,
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
    model: TEXT_MODEL,
    systemInstruction: EVA_SYSTEM_PROMPT,
    generationConfig: genConfig(TEXT_MODEL, "minimal", { responseMimeType: "application/json" }),
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
  await trackUsage("greeting", TEXT_MODEL, geminiUsage(result));
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
  if (after.appRole === "partner") return;
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
    if (d.evaNudgeSent || d.isOnboardingCompleted !== true || d.appRole === "partner" || isProActive(d)) continue;
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
// 11. РАССЫЛКА ОТ АДМИНИСТРАТОРА
// ==========================================
// Запуск без обновления приложения: в консоли Firebase → Firestore создать документ
// в коллекции admin_broadcasts с полями:
//   text   (string) — текст сообщения;
//   dryRun (boolean, необязательно) — true: только посчитать получателей, ничего не отправлять.
// Сообщение приходит каждому пользователю в чат с владельцем (a.eduardmail@gmail.com),
// пуш отправляет onNewChatMessage. Повторный запуск того же документа дублей не создаёт.
// Клиентам коллекция закрыта правилами (правил для неё нет), писать может только консоль/сервер.
exports.processAdminBroadcast = onDocumentCreated({ document: "admin_broadcasts/{broadcastId}", timeoutSeconds: 540, memory: "512MiB" }, async (event) => {
  const ref = event.data && event.data.ref;
  const d = (event.data && event.data.data()) || {};
  if (!ref) return;
  const text = String(d.text || "").trim();
  if (!text || text.length > 3000) {
    await ref.set({ status: "error", error: "Пустой текст или длиннее 3000 символов" }, { merge: true });
    return;
  }
  let senderUid = typeof d.senderUid === "string" && d.senderUid ? d.senderUid : null;
  if (!senderUid) {
    try {
      senderUid = (await getAuth().getUserByEmail(OWNER_EMAILS[0])).uid;
    } catch (e) {
      await ref.set({ status: "error", error: "Не найден аккаунт владельца: " + (e && e.message) }, { merge: true });
      return;
    }
  }
  const usersSnap = await db.collection("users").select().get();
  const targets = usersSnap.docs.map((x) => x.id).filter((id) => id !== senderUid && id !== SUPPORT_ADMIN_UID);
  if (d.dryRun === true) {
    await ref.set({ status: "dry_run", senderUid, total: targets.length, checkedAt: FieldValue.serverTimestamp() }, { merge: true });
    return;
  }
  await ref.set({ status: "sending", senderUid, total: targets.length, startedAt: FieldValue.serverTimestamp() }, { merge: true });
  const msgId = ("bc_" + event.params.broadcastId).slice(0, 120);
  let sent = 0, skipped = 0, failed = 0;
  for (let i = 0; i < targets.length; i += 200) {
    const chunk = targets.slice(i, i + 200);
    const results = await Promise.allSettled(chunk.map((uid) => {
      const chatId = [uid, senderUid].sort().join("_");
      return db.collection("chats").doc(chatId).collection("messages").doc(msgId).create({
        senderId: senderUid,
        receiverId: uid,
        text,
        type: "text",
        timestamp: FieldValue.serverTimestamp(),
        clientTs: Timestamp.now(),
        v: 2,
        via: "broadcast",
      });
    }));
    results.forEach((r) => {
      if (r.status === "fulfilled") sent++;
      else if (r.reason && r.reason.code === 6) skipped++; // уже отправлено ранее
      else failed++;
    });
    await ref.set({ sent, skipped, failed }, { merge: true });
    await sleep(1000); // плавно, чтобы не упереться в лимиты пушей
  }
  await ref.set({ status: "done", finishedAt: FieldValue.serverTimestamp() }, { merge: true });
  console.log(`[adminBroadcast] ${event.params.broadcastId}: sent ${sent}, skipped ${skipped}, failed ${failed}`);
});

// ==========================================
// 12. «ПРИГЛАСИ ПОДРУГУ» — неделя PRO обеим
// ==========================================
// У каждой пользовательницы свой код вида EVAXXXXX (referral_codes/{code} → uid).
// Подруга вводит код (экран «Пригласи подругу» или обычное поле промокода):
//   • подруге +7 дней PRO (один раз, аккаунту не больше 30 дней);
//   • пригласившей +7 дней PRO (до 10 наград) и пуш.
const REFERRAL_DAYS = 7;
const REFERRAL_MAX_REWARDS = 10;
const REFERRAL_MAX_ACCOUNT_AGE_DAYS = 30;
const REF_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function randomReferralCode() {
  let c = "EVA";
  for (let i = 0; i < 5; i++) c += REF_ALPHABET[Math.floor(Math.random() * REF_ALPHABET.length)];
  return c;
}

async function ensureReferralCode(uid) {
  const userRef = db.collection("users").doc(uid);
  const user = await userRef.get();
  const existing = user.exists ? user.data().referralCode : null;
  if (typeof existing === "string" && existing) return existing;
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = randomReferralCode();
    try {
      await db.collection("referral_codes").doc(code).create({ uid, createdAt: FieldValue.serverTimestamp() });
      await userRef.set({ referralCode: code }, { merge: true });
      return code;
    } catch (e) {
      if (e.code !== 6) throw e; // 6 = код занят, пробуем другой
    }
  }
  throw new HttpsError("internal", "Не удалось создать код. Попробуйте ещё раз.");
}

function extendPro(user, days) {
  const cur = user.proUntil && user.proUntil.toDate ? user.proUntil.toDate() : new Date();
  const base = isProActive(user) && cur > new Date() ? cur : new Date();
  return new Date(base.getTime() + days * DAY_MS);
}

async function accountAgeDays(uid) {
  try {
    const u = await getAuth().getUser(uid);
    const created = Date.parse(u.metadata.creationTime || "") || Date.now();
    return (Date.now() - created) / DAY_MS;
  } catch (e) {
    return 0;
  }
}

async function applyReferral(uid, code, inviterUid) {
  if (!inviterUid) throw new HttpsError("not-found", "Неверный промокод");
  if (inviterUid === uid) throw new HttpsError("failed-precondition", "Это твой собственный код — отправь его подруге 🌸");
  if (await accountAgeDays(uid) > REFERRAL_MAX_ACCOUNT_AGE_DAYS) {
    throw new HttpsError("failed-precondition", "Код подруги действует в первые 30 дней после регистрации.");
  }
  const userRef = db.collection("users").doc(uid);
  const inviterRef = db.collection("users").doc(inviterUid);
  const result = await db.runTransaction(async (tx) => {
    const [uSnap, iSnap] = await Promise.all([tx.get(userRef), tx.get(inviterRef)]);
    const user = uSnap.exists ? uSnap.data() : {};
    if (user.referredBy) throw new HttpsError("already-exists", "Код подруги уже применён");
    const until = extendPro(user, REFERRAL_DAYS);
    tx.set(userRef, {
      isPro: true,
      proUntil: Timestamp.fromDate(until),
      referredBy: inviterUid,
      referredAt: FieldValue.serverTimestamp(),
      usedPromoCodes: FieldValue.arrayUnion(code),
    }, { merge: true });
    let inviterRewarded = false;
    if (iSnap.exists) {
      const inviter = iSnap.data();
      const count = toInt(inviter.referralCount, 0);
      const upd = { referralCount: count + 1 };
      if (toInt(inviter.referralRewards, 0) < REFERRAL_MAX_REWARDS) {
        upd.isPro = true;
        upd.proUntil = Timestamp.fromDate(extendPro(inviter, REFERRAL_DAYS));
        upd.referralRewards = toInt(inviter.referralRewards, 0) + 1;
        inviterRewarded = true;
      }
      tx.set(inviterRef, upd, { merge: true });
    }
    return { until, inviterRewarded };
  });
  await db.collection("referral_codes").doc(code).set({ uses: FieldValue.increment(1), lastUsedAt: FieldValue.serverTimestamp() }, { merge: true }).catch(() => null);
  if (result.inviterRewarded) {
    await sendPush(inviterUid, "Подруга с тобой! 🎉", `Она присоединилась по твоему коду — тебе +${REFERRAL_DAYS} дней PRO 💗`, { type: "referral" });
  }
  // type "trial" — чтобы старые версии приложения показали обычное сообщение об активации.
  return { type: "trial", referral: true, days: REFERRAL_DAYS, proUntil: result.until.getTime() };
}

exports.getReferralInfo = onCall(async (request) => {
  const uid = requireAuth(request);
  const code = await ensureReferralCode(uid);
  const snap = await db.collection("users").doc(uid).get();
  const d = snap.exists ? snap.data() : {};
  const ageDays = await accountAgeDays(uid);
  return {
    code,
    days: REFERRAL_DAYS,
    invited: toInt(d.referralCount, 0),
    rewards: toInt(d.referralRewards, 0),
    maxRewards: REFERRAL_MAX_REWARDS,
    canEnterCode: !d.referredBy && ageDays <= REFERRAL_MAX_ACCOUNT_AGE_DAYS,
    referred: !!d.referredBy,
  };
});

// ==========================================
// 13. РАССЫЛКА ИЗ ПРИЛОЖЕНИЯ (экран «Рассылка» в админ-разделе)
// ==========================================
// Создаёт документ admin_broadcasts — дальше работает processAdminBroadcast.
exports.adminBroadcast = onCall(async (request) => {
  requireAuth(request);
  if (!canSeeStats(request)) throw new HttpsError("permission-denied", "Нет доступа.");
  const data = request.data || {};
  const action = data.action === "list" ? "list" : "create";
  if (action === "list") {
    const snap = await db.collection("admin_broadcasts").orderBy(FieldPath.documentId(), "desc").limit(20).get();
    return {
      items: snap.docs.map((x) => {
        const v = x.data();
        return {
          id: x.id,
          text: String(v.text || "").slice(0, 300),
          status: v.status || "queued",
          dryRun: v.dryRun === true,
          total: toInt(v.total, 0),
          sent: toInt(v.sent, 0),
          failed: toInt(v.failed, 0),
          at: v.startedAt && v.startedAt.toMillis ? v.startedAt.toMillis() : (v.checkedAt && v.checkedAt.toMillis ? v.checkedAt.toMillis() : 0),
        };
      }),
    };
  }
  const text = String(data.text || "").trim();
  if (text.length < 5 || text.length > 3000) throw new HttpsError("invalid-argument", "Текст от 5 до 3000 символов.");
  const dryRun = data.dryRun === true;
  const id = `${new Date(Date.now() + MSK_OFFSET_MS).toISOString().slice(0, 16).replace(/[-:T]/g, "")}_${dryRun ? "check" : "send"}_${Math.random().toString(36).slice(2, 6)}`;
  await db.collection("admin_broadcasts").doc(id).set({ text, dryRun, senderUid: request.auth.uid, createdAt: FieldValue.serverTimestamp(), createdBy: request.auth.uid });
  // Ждём результат проверки (обычно 1–3 с), чтобы сразу показать число получателей.
  if (dryRun) {
    for (let i = 0; i < 20; i++) {
      await sleep(500);
      const d = (await db.collection("admin_broadcasts").doc(id).get()).data() || {};
      if (d.status === "dry_run" || d.status === "error") return { id, status: d.status, total: toInt(d.total, 0), error: d.error || null };
    }
  }
  return { id, status: "queued" };
});

// ==========================================
// 14. РЕЖИМ ПАРТНЁРА (v1.6)
// ==========================================
// Она получает код (PR + 6 символов) и отправляет партнёру. Партнёр ставит «Мою Еву»,
// при регистрации жмёт «Я партнёр» и вводит код — его аккаунт становится партнёрским
// (appRole: "partner") и видит только: имя, фазу, день цикла, сколько дней до месячных.
// Никаких симптомов, настроения, веса и питания. Она может отключить партнёра в любой момент.
// partnerships/{ownerUid}: { ownerUid, partnerUid, createdAt, lastSignal, lastReply }

const PARTNER_SIGNALS = {
  hug: { emoji: "🤗", text: "Обними меня" },
  sweet: { emoji: "🍫", text: "Хочу чего-нибудь вкусного" },
  space: { emoji: "🌙", text: "Мне нужно немного тишины" },
  hard: { emoji: "🫶", text: "Сегодня тяжёлый день — будь рядом" },
  love: { emoji: "💗", text: "Люблю тебя" },
};
const PARTNER_REPLIES = {
  ok: "❤️ Понял, я рядом",
  onway: "🏃 Уже иду",
  love: "💗 Люблю тебя",
};

function firstName(d, fallback) {
  return String((d && d.name) || "").trim().split(/\s+/)[0] || fallback;
}

function randomPartnerCode() {
  let c = "PR";
  for (let i = 0; i < 6; i++) c += REF_ALPHABET[Math.floor(Math.random() * REF_ALPHABET.length)];
  return c;
}

async function ensurePartnerCode(uid) {
  const userRef = db.collection("users").doc(uid);
  const user = await userRef.get();
  const existing = user.exists ? user.data().partnerCode : null;
  if (typeof existing === "string" && existing) return existing;
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = randomPartnerCode();
    try {
      await db.collection("partner_codes").doc(code).create({ uid, createdAt: FieldValue.serverTimestamp() });
      await userRef.set({ partnerCode: code }, { merge: true });
      return code;
    } catch (e) {
      if (e.code !== 6) throw e;
    }
  }
  throw new HttpsError("internal", "Не удалось создать код. Попробуйте ещё раз.");
}

function mskDayIndex(ms) {
  return Math.floor((ms + MSK_OFFSET_MS) / DAY_MS);
}

/** Что видит партнёр. Считаем по московским дням, задержку не «перепрыгиваем». */
function partnerCycleView(d, now = Date.now()) {
  const out = { mode: "nodata", phaseKey: null, cycleDay: null, daysToPeriod: null, cycleLength: null, periodDuration: null, pregnancyWeek: null };
  if (!d) return out;
  if (d.isPregnant === true || d.appMode === "pregnancy") {
    const s = userSnapshotForEva(d, now);
    out.mode = "pregnancy";
    out.pregnancyWeek = s.pregnancyWeek;
    return out;
  }
  const start = tsToMs(d.lastPeriodStartDate);
  if (!start) return out;
  const len = Math.min(45, Math.max(20, toInt(d.cycleLength, 28)));
  const period = Math.min(10, Math.max(2, toInt(d.periodDuration, 5)));
  const diff = mskDayIndex(now) - mskDayIndex(start);
  if (diff < 0) return out;
  out.cycleLength = len;
  out.periodDuration = period;
  out.cycleDay = diff + 1;
  if (diff >= len) {
    out.mode = "delay"; // новый цикл ещё не отмечен
    return out;
  }
  const day = diff + 1;
  const ov = Math.max(period + 2, len - 14);
  let key = "luteal";
  if (day <= period) key = "menstruation";
  else if (day < ov - 1) key = "follicular";
  else if (day <= ov + 1) key = "ovulation";
  if (key === "luteal" && len - day + 1 <= 5) key = "pms";
  out.mode = "cycle";
  out.phaseKey = key;
  out.daysToPeriod = len - day + 1;
  return out;
}

async function loadPartnership(ownerUid) {
  const snap = await db.collection("partnerships").doc(ownerUid).get();
  return snap.exists ? snap.data() : null;
}

function signalOut(s) {
  if (!s || !s.kind) return null;
  const meta = PARTNER_SIGNALS[s.kind] || PARTNER_REPLIES[s.kind];
  return {
    kind: s.kind,
    text: meta ? (meta.text ? `${meta.emoji} ${meta.text}` : meta) : "",
    at: tsToMs(s.at),
  };
}

async function unlinkPair(ownerUid, partnerUid) {
  const batch = db.batch();
  batch.delete(db.collection("partnerships").doc(ownerUid));
  batch.set(db.collection("users").doc(ownerUid), { partnerUid: FieldValue.delete() }, { merge: true });
  if (partnerUid) batch.set(db.collection("users").doc(partnerUid), { partnerOf: FieldValue.delete() }, { merge: true });
  await batch.commit();
}

/**
 * partnerLink({action, ...}):
 *  - "info"   (она)     → { code, partner: {name} | null, lastSignal, lastReply }
 *  - "join"   (партнёр) {code, name} → привязка, аккаунт становится партнёрским
 *  - "view"   (партнёр) → { linked, name, cycle, lastSignal, lastReply }
 *  - "signal" (она)     {kind} → пуш партнёру
 *  - "reply"  (партнёр) {kind} → пуш ей
 *  - "unlink" (любой из двоих)
 */
exports.partnerLink = onCall(async (request) => {
  const uid = requireAuth(request);
  const p = request.data || {};
  const action = String(p.action || "");
  const meRef = db.collection("users").doc(uid);
  const meSnap = await meRef.get();
  const me = meSnap.exists ? meSnap.data() : {};

  if (action === "info") {
    if (me.appRole === "partner") throw new HttpsError("failed-precondition", "Это партнёрский аккаунт");
    const code = await ensurePartnerCode(uid);
    let partner = null;
    let ps = null;
    if (me.partnerUid) {
      const pSnap = await db.collection("users").doc(me.partnerUid).get();
      if (pSnap.exists && pSnap.data().partnerOf === uid) {
        partner = { uid: me.partnerUid, name: firstName(pSnap.data(), "Партнёр") };
        ps = await loadPartnership(uid);
      } else {
        await unlinkPair(uid, null); // партнёр удалил аккаунт или отвязался
      }
    }
    return { code, partner, lastSignal: signalOut(ps && ps.lastSignal), lastReply: signalOut(ps && ps.lastReply) };
  }

  if (action === "join") {
    const code = String(p.code || "").trim().toUpperCase().replace(/\s+/g, "");
    const name = String(p.name || "").trim().slice(0, 40);
    if (!/^PR[A-Z2-9]{6}$/.test(code)) throw new HttpsError("not-found", "Такого кода нет");
    if (me.isOnboardingCompleted === true && me.appRole !== "partner") {
      throw new HttpsError("failed-precondition", "Этот аккаунт уже заполнен как женский. Для партнёра нужен отдельный аккаунт.");
    }
    const codeSnap = await db.collection("partner_codes").doc(code).get();
    if (!codeSnap.exists) throw new HttpsError("not-found", "Такого кода нет");
    const ownerUid = codeSnap.data().uid;
    if (ownerUid === uid) throw new HttpsError("failed-precondition", "Это твой собственный код");
    const ownerRef = db.collection("users").doc(ownerUid);
    const result = await db.runTransaction(async (tx) => {
      const oSnap = await tx.get(ownerRef);
      if (!oSnap.exists) throw new HttpsError("not-found", "Такого кода нет");
      const o = oSnap.data();
      if (o.partnerUid && o.partnerUid !== uid) {
        throw new HttpsError("already-exists", "К этому коду уже подключён партнёр. Попроси её отключить старую связь.");
      }
      if (me.partnerOf && me.partnerOf !== ownerUid) {
        throw new HttpsError("already-exists", "Ты уже подключён к другому человеку. Сначала отключись в настройках.");
      }
      tx.set(ownerRef, { partnerUid: uid }, { merge: true });
      tx.set(meRef, {
        appRole: "partner",
        partnerOf: ownerUid,
        name: name || me.name || "Партнёр",
        isOnboardingCompleted: true,
        joinDate: me.joinDate || FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(db.collection("partnerships").doc(ownerUid), {
        ownerUid, partnerUid: uid, createdAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return { ownerName: firstName(o, "она") };
    });
    await sendPush(ownerUid, "Партнёр подключился 💗", `${name || "Он"} теперь знает, когда тебе нужна поддержка. Настройки — в Профиле → «Режим партнёра».`, { type: "partner", to: "owner" });
    return { ok: true, name: result.ownerName };
  }

  if (action === "view") {
    if (!me.partnerOf) return { linked: false };
    const oSnap = await db.collection("users").doc(me.partnerOf).get();
    if (!oSnap.exists || oSnap.data().partnerUid !== uid) {
      await meRef.set({ partnerOf: FieldValue.delete() }, { merge: true });
      return { linked: false };
    }
    const o = oSnap.data();
    const ps = await loadPartnership(me.partnerOf);
    return {
      linked: true,
      ownerUid: me.partnerOf,
      name: firstName(o, "Она"),
      cycle: partnerCycleView(o),
      lastSignal: signalOut(ps && ps.lastSignal),
      lastReply: signalOut(ps && ps.lastReply),
    };
  }

  if (action === "signal") {
    const kind = String(p.kind || "");
    if (!PARTNER_SIGNALS[kind]) throw new HttpsError("invalid-argument", "Неизвестный сигнал");
    if (!me.partnerUid) throw new HttpsError("failed-precondition", "Партнёр ещё не подключён");
    const s = PARTNER_SIGNALS[kind];
    await db.collection("partnerships").doc(uid).set({ lastSignal: { kind, at: FieldValue.serverTimestamp() }, lastReply: FieldValue.delete() }, { merge: true });
    await sendPush(me.partnerUid, `${firstName(me, "Она")}: ${s.emoji}`, s.text, { type: "partner" });
    return { ok: true };
  }

  if (action === "reply") {
    const kind = String(p.kind || "");
    if (!PARTNER_REPLIES[kind]) throw new HttpsError("invalid-argument", "Неизвестный ответ");
    if (!me.partnerOf) throw new HttpsError("failed-precondition", "Связь не найдена");
    await db.collection("partnerships").doc(me.partnerOf).set({ lastReply: { kind, at: FieldValue.serverTimestamp() } }, { merge: true });
    await sendPush(me.partnerOf, firstName(me, "Партнёр"), PARTNER_REPLIES[kind], { type: "partner", to: "owner" });
    return { ok: true };
  }

  if (action === "unlink") {
    if (me.appRole === "partner") {
      if (me.partnerOf) {
        const oSnap = await db.collection("users").doc(me.partnerOf).get();
        if (oSnap.exists && oSnap.data().partnerUid === uid) await unlinkPair(me.partnerOf, uid);
        else await meRef.set({ partnerOf: FieldValue.delete() }, { merge: true });
      }
    } else if (me.partnerUid) {
      const partnerUid = me.partnerUid;
      await unlinkPair(uid, partnerUid);
      await sendPush(partnerUid, "Моя Ева", `${firstName(me, "Она")} отключила режим партнёра.`, { type: "partner" });
    }
    return { ok: true };
  }

  throw new HttpsError("invalid-argument", "Неизвестное действие");
});

/** Утренние подсказки партнёру: за 5 дней (ПМС), за 2 дня и в первый день месячных. */
function partnerDailyText(name, v) {
  if (v.mode !== "cycle") return null;
  if (v.cycleDay === 1) return { title: `${name}: 1-й день цикла`, body: "Сегодня может не хватать сил. Тепло, чай и чуть меньше дел — лучшая поддержка 💗" };
  if (v.daysToPeriod === 2) return { title: "Через 2 дня — месячные", body: "Хороший момент порадовать её любимыми вкусностями 🍫" };
  if (v.daysToPeriod === 5) return { title: "Начинаются дни перед циклом", body: "У неё может быть больше усталости и эмоций. Терпение и забота — советы в приложении 🤍" };
  return null;
}

exports.partnerDaily = onSchedule({ schedule: "7 10 * * *", timeZone: "Europe/Moscow", timeoutSeconds: 300, memory: "256MiB" }, async () => {
  const snap = await db.collection("partnerships").get();
  let sent = 0;
  for (const doc of snap.docs) {
    const { ownerUid, partnerUid } = doc.data();
    if (!ownerUid || !partnerUid) continue;
    try {
      const oSnap = await db.collection("users").doc(ownerUid).get();
      if (!oSnap.exists || oSnap.data().partnerUid !== partnerUid) continue;
      const o = oSnap.data();
      const t = partnerDailyText(firstName(o, "Она"), partnerCycleView(o));
      if (!t) continue;
      await sendPush(partnerUid, t.title, t.body, { type: "partner" });
      sent++;
    } catch (e) {
      console.error("[partnerDaily]", doc.id, e && e.message);
    }
  }
  if (sent) console.log(`[partnerDaily] sent ${sent}`);
});

// ==========================================
// 15. СКАНЕР СОСТАВА (v1.7): продукт или косметика по фото этикетки
// ==========================================
// Ответ — строгий JSON для экрана результата. Расходует бесплатный лимит «scan».
// История: users/{uid}/label_scans (последние сканы).

// Общее правило для всех чатов Евы: обращение по имени.
const NAME_RULE = "\n\nОБРАЩЕНИЕ: называй пользовательницу только так, как её имя записано в досье, без уменьшительно-ласкательных форм (не «Сашенька», если в досье «Александра»). Имя — не чаще одного раза в сообщении, можно и без него. Пиши только по-русски: без английских слов в тексте (кроме названий брендов и средств).";

const COSMETOLOGIST_PROMPT = `Ты — Ева, ИИ-косметолог и заботливая подруга в приложении «Моя Ева». Помогаешь с уходом за кожей, волосами и выбором косметики с учётом фазы цикла, возраста и беременности.

ПРАВИЛА:
1. Обращайся на «ты», тепло, в женском роде, без приветствия в каждом сообщении. Пиши коротко и по делу, списками, с 1–2 эмодзи.
2. Если тип кожи неизвестен — в начале разговора мягко спроси (сухая, жирная, комбинированная, нормальная, чувствительная) и учитывай ответ дальше.
3. Связывай советы с фазой цикла: месячные — бережный уход и увлажнение; фолликулярная — хорошее время для активов и процедур; овуляция — кожа в лучшей форме, лёгкие текстуры; лютеиновая и дни перед циклом — больше себума и воспалений, точечный уход, не экспериментировать с новыми средствами.
4. Беременность и кормление: не рекомендуй ретиноиды, высокие концентрации салициловой кислоты, гидрохинон; всегда советуй согласовать с врачом.
5. Разбор состава (INCI): назови полезные компоненты, на что обратить внимание, кому подойдёт. Не пугай «химией», без мифов.
6. Ты не врач-дерматолог. При высыпаниях, которые не проходят, сильном раздражении, подозрительных родинках — советуй обратиться к дерматологу.
7. Предлагай доступные средства из российских магазинов (аптечные марки, масс-маркет), без рекламы конкретных брендов как «единственно правильных».
8. Не переспрашивай то, что уже известно из досье, анкеты, анализа кожи или прошлых сообщений (тип кожи, что беспокоит, бюджет, время на уход). Опирайся на это сразу. Бюджет спрашивай одним коротким вопросом, только если его нигде нет.
9. Симптомы из календаря упоминай, только если они реально связаны с кожей или волосами (высыпания, сухость, жирность, отёки, выпадение). Остальные (боль в груди, бессонница и т.п.) в разговоре об уходе не упоминай.
10. «Моя полка косметики» в памяти — это средства, которые у неё уже есть дома. Опирайся на них: собирай уход утром и вечером из того, что есть; честно говори, если средства дублируют друг друга (одно можно пока убрать), конфликтуют (например, ретинол с кислотами в один вечер), не подходят её типу кожи или нежелательны при беременности; советуй докупить только то, чего реально не хватает (обычно SPF, мягкое очищение, увлажнение). Новые покупки не навязывай.`;

const SCAN_FOOD_PROMPT = `Ты — нутрициолог. На фото — этикетка или упаковка продукта из магазина (состав и/или таблица пищевой ценности).
Прочитай её и верни ТОЛЬКО JSON:
{
 "ok": true,
 "productName": "краткое название продукта",
 "per100": {"kcal": 0, "protein": 0, "fat": 0, "carbs": 0, "sugar": null, "fiber": null, "salt": null},
 "packageG": null,
 "score": "good" | "ok" | "limit",
 "verdict": "1–2 предложения: стоит ли брать именно ей, с учётом цели и фазы цикла из досье",
 "pros": ["до 3 коротких плюсов"],
 "cons": ["до 3 коротких минусов"],
 "flags": ["из списка: много сахара, подсластители, трансжиры, пальмовое масло, много соли, много насыщенных жиров, ароматизаторы, красители, консерванты, мало белка, высокая калорийность"],
 "additives": [{"code": "E330", "name": "лимонная кислота", "note": "безопасна"}],
 "portionTip": "сколько граммов разумно съесть за раз под её норму",
 "phaseTip": "1 предложение, как этот продукт сочетается с её текущей фазой цикла (или пусто)"
}
Правила: числа — на 100 г (или 100 мл) из таблицы на этикетке; если таблицы нет — оцени по составу и типу продукта. Нет данных — null. Состав читай внимательно: порядок ингредиентов = по убыванию доли. Не выдумывай E-добавки, которых нет на фото. Без медицинских диагнозов.
Если на фото косметика или бытовая химия (крем, шампунь, сыворотка, INCI-состав) — верни {"ok": false, "wrongKind": "cosmetic"}.
Если на фото не этикетка продукта — верни {"ok": false, "reason": "коротко, что не так с фото"}.`;

const SCAN_COSMETIC_PROMPT = `Ты — косметолог-химик. На фото — упаковка или состав (INCI) косметического средства.
Прочитай и верни ТОЛЬКО JSON:
{
 "ok": true,
 "productName": "название, если видно",
 "productType": "крем / сыворотка / тоник / шампунь / SPF / ...",
 "score": "good" | "ok" | "limit",
 "verdict": "1–2 предложения: подойдёт ли ей с учётом типа кожи, возраста, беременности и фазы цикла из досье",
 "good": [{"name": "ниацинамид", "why": "выравнивает тон, снижает жирность"}],
 "watch": [{"name": "отдушка (parfum)", "why": "может раздражать чувствительную кожу"}],
 "skinTypes": ["кому подходит: сухая, жирная, комбинированная, нормальная, чувствительная"],
 "pregnancy": "ok" | "caution" | "avoid",
 "pregnancyNote": "коротко почему",
 "howToUse": "когда и как наносить (утро/вечер, частота, SPF)",
 "phaseTip": "1 предложение про использование в её текущую фазу цикла (или пусто)"
}
Правила: опирайся только на компоненты, которые видно на фото. Без мифов про «химию» и парабены. Ретиноиды, высокие % кислот, гидрохинон — "pregnancy": "avoid" или "caution". До 5 пунктов в good и watch.
Если на фото продукт питания или напиток (еда, этикетка с КБЖУ) — верни {"ok": false, "wrongKind": "food"}.
Если состава (INCI) на фото не видно, но читается название известного средства (бренд + линейка) — разбери по его известному составу: верни "ok": true, добавь "basedOnName": true, а в "verdict" первой фразой честно скажи, что состав взят по названию и его стоит сверить с упаковкой. Ничего не выдумывай про неизвестные средства.
Если на фото не косметика или ни состав, ни название не читаются — верни {"ok": false, "reason": "коротко, что не так с фото"}.`;

async function scanContext(uid) {
  const [uSnap, gSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("users").doc(uid).collection("nutrition_goal").doc("current").get().catch(() => null),
  ]);
  const d = uSnap.exists ? uSnap.data() : {};
  const s = userSnapshotForEva(d);
  const g = gSnap && gSnap.exists ? gSnap.data() : {};
  const lines = [];
  if (s.name) lines.push(`Имя: ${s.name}`);
  if (d.age) lines.push(`Возраст: ${toInt(d.age)}`);
  if (s.goal) lines.push(`Цель: ${s.goal}`);
  if (toInt(g.calories) > 0) lines.push(`Норма: ${toInt(g.calories)} ккал, Б ${toInt(g.protein)} / Ж ${toInt(g.fat)} / У ${toInt(g.carbs)}`);
  if (s.pregnancyWeek) lines.push(`Беременность: ${s.pregnancyWeek}-я неделя`);
  else if (s.phase) lines.push(`Фаза цикла: ${s.phase} (день ${s.cycleDay})`);
  if (d.skinType) lines.push(`Тип кожи: ${String(d.skinType).slice(0, 40)}`);
  return lines.join("\n") || "(профиль не заполнен)";
}

function cleanScanJson(raw, kind) {
  let j;
  try {
    j = JSON.parse(String(raw || "").replace(/^```(?:json)?\s*|\s*```$/g, ""));
  } catch (e) {
    return { ok: false, reason: "Не удалось прочитать этикетку. Сфотографируй состав крупнее и при хорошем свете." };
  }
  if (j && j.ok === false && (j.wrongKind === "food" || j.wrongKind === "cosmetic") && j.wrongKind !== kind) {
    // Сфотографировали не в том режиме — клиент сам переключит режим и повторит разбор.
    return { ok: false, wrongKind: j.wrongKind, reason: j.wrongKind === "cosmetic" ? "Похоже, это косметика" : "Похоже, это продукт питания" };
  }
  if (!j || j.ok === false) return { ok: false, reason: String((j && j.reason) || "Не получилось распознать этикетку").slice(0, 200) };
  const str = (v, n = 300) => (v === null || v === undefined ? "" : String(v).slice(0, n));
  const arr = (v, n = 5) => (Array.isArray(v) ? v.slice(0, n) : []);
  const num = (v) => (v === null || v === undefined || v === "" || !Number.isFinite(Number(v)) ? null : Math.round(Number(v) * 10) / 10);
  const score = ["good", "ok", "limit"].includes(j.score) ? j.score : "ok";
  if (kind === "food") {
    const p = j.per100 || {};
    return {
      ok: true, kind, score,
      productName: str(j.productName, 80) || "Продукт",
      per100: { kcal: num(p.kcal), protein: num(p.protein), fat: num(p.fat), carbs: num(p.carbs), sugar: num(p.sugar), fiber: num(p.fiber), salt: num(p.salt) },
      packageG: num(j.packageG),
      verdict: str(j.verdict), pros: arr(j.pros, 3).map((x) => str(x, 120)), cons: arr(j.cons, 3).map((x) => str(x, 120)),
      flags: arr(j.flags, 8).map((x) => str(x, 40)),
      additives: arr(j.additives, 12).map((a) => ({ code: str(a && a.code, 12), name: str(a && a.name, 60), note: str(a && a.note, 100) })),
      portionTip: str(j.portionTip, 200), phaseTip: str(j.phaseTip, 200),
    };
  }
  const pr = ["ok", "caution", "avoid"].includes(j.pregnancy) ? j.pregnancy : "caution";
  const items = (v) => arr(v, 5).map((x) => ({ name: str(x && x.name, 60), why: str(x && x.why, 140) }));
  return {
    ok: true, kind, score,
    productName: str(j.productName, 80) || "Средство", productType: str(j.productType, 40),
    verdict: str(j.verdict), good: items(j.good), watch: items(j.watch),
    skinTypes: arr(j.skinTypes, 5).map((x) => str(x, 30)),
    pregnancy: pr, pregnancyNote: str(j.pregnancyNote, 200),
    howToUse: str(j.howToUse, 240), phaseTip: str(j.phaseTip, 200),
    basedOnName: j.basedOnName === true,
  };
}

exports.scanLabel = onCall({ maxInstances: 20, timeoutSeconds: 90, memory: "512MiB" }, async (request) => {
  const uid = requireAuth(request);
  const p = request.data || {};
  const kind = p.kind === "cosmetic" ? "cosmetic" : "food";
  const image = typeof p.imageBase64 === "string" ? p.imageBase64 : "";
  if (!image || image.length > 8 * 1024 * 1024) throw new HttpsError("invalid-argument", "Нет фото или оно слишком большое");

  const quota = await consumeQuota(uid, "scan");
  if (!quota.allowed) throw quota.limit ? new HttpsError("failed-precondition", PRO_LIMIT_TEXT) : new HttpsError("resource-exhausted", "QUOTA_EXCEEDED");
  try {
    const ctx = await scanContext(uid);
    const model = getGenAI().getGenerativeModel({
      model: VISION_MODEL,
      systemInstruction: `${kind === "food" ? SCAN_FOOD_PROMPT : SCAN_COSMETIC_PROMPT}\n\nДОСЬЕ:\n${ctx}`,
      generationConfig: genConfig(VISION_MODEL, "low", { responseMimeType: "application/json" }),
    });
    const result = await generateWithRetry(() => model.generateContent(["Разбери этикетку на фото.", { inlineData: { data: image, mimeType: "image/jpeg" } }]));
    await trackUsage(`scan_${kind}`, VISION_MODEL, geminiUsage(result));
    const out = cleanScanJson(result && result.response && result.response.text(), kind);
    if (!out.ok) {
      await refundQuota(uid, quota); // нечитаемое фото не списываем
      return out;
    }
    const ref = await db.collection("users").doc(uid).collection("label_scans").add({ ...out, at: FieldValue.serverTimestamp() });
    return { ...out, id: ref.id, left: quota.pro ? null : quota.left };
  } catch (e) {
    console.error("[scanLabel]", uid, e && e.message);
    await refundQuota(uid, quota);
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("unavailable", "Ева временно недоступна. Попробуй ещё раз.");
  }
});

// ==========================================
// 16. ЧЕЛЛЕНДЖИ С ПОДРУГАМИ (v1.8)
// ==========================================
// challenges/{id}: { template, title, emoji, ownerUid, code, startKey, days, members[], names{uid}, checkins{uid:[dayKey]} }
// challenge_codes/{code} → { id }. Клиент читает и пишет только через callable `challenge`.

const CHALLENGE_TEMPLATES = {
  water: { title: "Вода каждый день", emoji: "💧", task: "Выпить 8 стаканов воды" },
  nosugar: { title: "Неделя без сладкого", emoji: "🍬", task: "Ни сладостей, ни сладких напитков" },
  veggies: { title: "Овощи в каждый приём", emoji: "🥦", task: "Овощи или зелень в каждом приёме пищи" },
  walk: { title: "Прогулка 30 минут", emoji: "🚶‍♀️", task: "Пройтись минимум 30 минут" },
  sleep: { title: "Спать до 23:30", emoji: "🌙", task: "Лечь спать до 23:30" },
  breakfast: { title: "Белковый завтрак", emoji: "🍳", task: "Завтрак с белком: яйца, творог, йогурт" },
};
const CHALLENGE_DAYS = 7;
const CUSTOM_CHALLENGE_EMOJI = ["⭐", "💪", "🧘‍♀️", "📚", "🥗", "🏃‍♀️", "💧", "🌿", "😴", "🍎", "✨", "❤️"];
const CHALLENGE_MAX_MEMBERS = 10;

function mskDayKey(ms = Date.now()) {
  return new Date(ms + MSK_OFFSET_MS).toISOString().slice(0, 10);
}
function dayKeyToIndex(key) {
  return Math.floor(Date.parse(`${key}T00:00:00Z`) / DAY_MS);
}

function challengeOut(id, c, uid) {
  const today = mskDayKey();
  const dayNum = dayKeyToIndex(today) - dayKeyToIndex(c.startKey) + 1;
  const members = (c.members || []).map((m) => {
    const keys = (c.checkins && c.checkins[m]) || [];
    const marks = [];
    for (let i = 0; i < c.days; i++) {
      const k = new Date((dayKeyToIndex(c.startKey) + i) * DAY_MS).toISOString().slice(0, 10);
      marks.push(keys.includes(k));
    }
    return { uid: m, name: (c.names && c.names[m]) || "Подруга", me: m === uid, done: keys.length, marks };
  }).sort((a, b) => b.done - a.done);
  const t = CHALLENGE_TEMPLATES[c.template] || {};
  return {
    id, code: c.code, template: c.template, title: c.title, emoji: c.emoji, task: c.task || t.task || "",
    days: c.days, startKey: c.startKey, dayNum,
    status: dayNum < 1 ? "soon" : (dayNum > c.days ? "finished" : "active"),
    checkedToday: ((c.checkins && c.checkins[uid]) || []).includes(today),
    isOwner: c.ownerUid === uid,
    members,
  };
}

async function randomChallengeCode() {
  for (let attempt = 0; attempt < 6; attempt++) {
    let code = "CH";
    for (let i = 0; i < 6; i++) code += REF_ALPHABET[Math.floor(Math.random() * REF_ALPHABET.length)];
    const snap = await db.collection("challenge_codes").doc(code).get();
    if (!snap.exists) return code;
  }
  throw new HttpsError("internal", "Не удалось создать код");
}

exports.challenge = onCall(async (request) => {
  const uid = requireAuth(request);
  const p = request.data || {};
  const action = String(p.action || "");
  const userSnap = await db.collection("users").doc(uid).get();
  const me = userSnap.exists ? userSnap.data() : {};
  const myName = firstName(me, "Подруга");

  if (action === "list") {
    const snap = await db.collection("challenges").where("members", "array-contains", uid).get();
    const items = snap.docs.map((d) => challengeOut(d.id, d.data(), uid))
      .sort((a, b) => (a.status === "finished") - (b.status === "finished") || b.startKey.localeCompare(a.startKey))
      .slice(0, 20);
    return { items, templates: Object.entries(CHALLENGE_TEMPLATES).map(([key, t]) => ({ key, ...t })) };
  }

  if (action === "create") {
    const key = String(p.template || "");
    let t = CHALLENGE_TEMPLATES[key];
    let days = CHALLENGE_DAYS;
    if (key === "custom") {
      // Свой челлендж: название, задание на день, эмодзи и длительность задаёт пользователь.
      const clean = (v, n) => String(v || "").replace(/https?:\/\/\S+|www\.\S+/gi, "").replace(/\s+/g, " ").trim().slice(0, n);
      const title = clean(p.title, 40);
      const task = clean(p.task, 100);
      if (title.length < 3) throw new HttpsError("invalid-argument", "Придумай название — хотя бы 3 буквы");
      if (task.length < 3) throw new HttpsError("invalid-argument", "Опиши, что делать каждый день");
      const emoji = CUSTOM_CHALLENGE_EMOJI.includes(p.emoji) ? p.emoji : "⭐";
      days = [7, 14, 21, 30].includes(Number(p.days)) ? Number(p.days) : CHALLENGE_DAYS;
      t = { title, emoji, task };
    }
    if (!t) throw new HttpsError("invalid-argument", "Неизвестный челлендж");
    const active = await db.collection("challenges").where("members", "array-contains", uid).get();
    if (active.docs.filter((d) => challengeOut(d.id, d.data(), uid).status !== "finished").length >= 5) {
      throw new HttpsError("failed-precondition", "Можно участвовать максимум в 5 челленджах одновременно");
    }
    const code = await randomChallengeCode();
    const ref = db.collection("challenges").doc();
    const c = {
      template: key, title: t.title, emoji: t.emoji, ownerUid: uid, code,
      ...(key === "custom" ? { task: t.task } : {}),
      startKey: mskDayKey(), days,
      members: [uid], names: { [uid]: myName }, checkins: { [uid]: [] },
      createdAt: FieldValue.serverTimestamp(),
    };
    await db.batch().set(ref, c).set(db.collection("challenge_codes").doc(code), { id: ref.id }).commit();
    return challengeOut(ref.id, c, uid);
  }

  if (action === "join") {
    const code = String(p.code || "").trim().toUpperCase().replace(/\s+/g, "");
    if (!/^CH[A-Z2-9]{6}$/.test(code)) throw new HttpsError("not-found", "Такого кода нет");
    const codeSnap = await db.collection("challenge_codes").doc(code).get();
    if (!codeSnap.exists) throw new HttpsError("not-found", "Такого кода нет");
    const ref = db.collection("challenges").doc(codeSnap.data().id);
    const out = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) throw new HttpsError("not-found", "Челлендж не найден");
      const c = s.data();
      if ((c.members || []).includes(uid)) return { c, joined: false };
      const view = challengeOut(s.id, c, uid);
      if (view.status === "finished") throw new HttpsError("failed-precondition", "Этот челлендж уже закончился");
      if ((c.members || []).length >= CHALLENGE_MAX_MEMBERS) throw new HttpsError("failed-precondition", "В челлендже уже 10 участниц");
      tx.update(ref, {
        members: FieldValue.arrayUnion(uid),
        [`names.${uid}`]: myName,
        [`checkins.${uid}`]: [],
      });
      c.members = [...(c.members || []), uid];
      c.names = { ...(c.names || {}), [uid]: myName };
      c.checkins = { ...(c.checkins || {}), [uid]: [] };
      return { c, joined: true };
    });
    if (out.joined) {
      await sendPush(out.c.ownerUid, `${out.c.emoji} ${out.c.title}`, `${myName} присоединилась к челленджу!`, { type: "challenge", id: ref.id });
    }
    return challengeOut(ref.id, out.c, uid);
  }

  const id = String(p.id || "");
  if (!/^[A-Za-z0-9]{10,40}$/.test(id)) throw new HttpsError("invalid-argument", "Нет id");
  const ref = db.collection("challenges").doc(id);

  if (action === "get") {
    const s = await ref.get();
    if (!s.exists || !(s.data().members || []).includes(uid)) throw new HttpsError("not-found", "Челлендж не найден");
    return challengeOut(id, s.data(), uid);
  }

  if (action === "checkin") {
    const today = mskDayKey();
    const c = await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists || !(s.data().members || []).includes(uid)) throw new HttpsError("not-found", "Челлендж не найден");
      const data = s.data();
      const view = challengeOut(id, data, uid);
      if (view.status !== "active") throw new HttpsError("failed-precondition", view.status === "soon" ? "Челлендж ещё не начался" : "Челлендж уже закончился");
      const mine = (data.checkins && data.checkins[uid]) || [];
      if (!mine.includes(today)) {
        tx.update(ref, { [`checkins.${uid}`]: FieldValue.arrayUnion(today) });
        data.checkins = { ...(data.checkins || {}), [uid]: [...mine, today] };
      }
      return data;
    });
    return challengeOut(id, c, uid);
  }

  if (action === "leave") {
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) return;
      const c = s.data();
      const members = (c.members || []).filter((m) => m !== uid);
      if (!members.length) {
        tx.delete(ref);
        tx.delete(db.collection("challenge_codes").doc(c.code));
        return;
      }
      tx.update(ref, {
        members: FieldValue.arrayRemove(uid),
        [`names.${uid}`]: FieldValue.delete(),
        [`checkins.${uid}`]: FieldValue.delete(),
        ...(c.ownerUid === uid ? { ownerUid: members[0] } : {}),
      });
    });
    return { ok: true };
  }

  throw new HttpsError("invalid-argument", "Неизвестное действие");
});

// ==========================================
// 17. КУРС «30 ДНЕЙ С ЕВОЙ» — напоминания (v1.8)
// ==========================================
// Прогресс курса пишет клиент в users/{uid}.course = { startedAt, done: [1..30], lastDoneKey: "YYYY-MM-DD", active: true }.
// Уроки 1–3 бесплатно, с 4-го — PRO (проверяет клиент; напоминание тоже не шлём без PRO).

const COURSE_TITLES = [
  "Тарелка, которая работает", "Белок — твой союзник", "Вода и голод", "Сахар без запретов", "Сон и аппетит",
  "Голод или скука?", "Итоги первой недели", "Твой цикл и тарелка", "Месячные: железо и тепло", "Фолликулярная фаза: энергия",
  "Овуляция: лёгкость", "Лютеиновая фаза: тяга к сладкому", "ПМС и настроение", "Итоги второй недели", "Читаем этикетку",
  "Скрытый сахар", "Перекусы без вины", "Готовим на 3 дня", "Кафе и доставка", "Праздники и гости",
  "Итоги третьей недели", "Движение в радость", "Кожа и питание", "Стресс и еда", "Сон и восстановление",
  "Добрые слова себе", "Привычки, которые останутся", "Твой список «работает для меня»", "Тело, которое ты слышишь", "Финиш и новый план",
];
const COURSE_FREE_DAYS = 3;

/** Какой урок сегодня доступен (или null). Один урок в день. */
function courseNextDay(course, todayKey) {
  if (!course || course.active !== true) return null;
  const done = Array.isArray(course.done) ? course.done.map((n) => toInt(n)).filter((n) => n >= 1 && n <= 30) : [];
  const next = done.length ? Math.max(...done) + 1 : 1;
  if (next > 30) return null;
  if (course.lastDoneKey === todayKey) return null; // сегодня урок уже пройден
  return next;
}

// Один вечерний пуш на человека: урок курса и/или отметка в челленджах вместе.
// Раньше было два пуша (19:37 и 20:17) — вечером приходило слишком много.
// Не шлём, если пользователь выключил «Курс и челленджи» в Настройках (programRemindersOff).
exports.courseReminder = onSchedule({ schedule: "37 19 * * *", timeZone: "Europe/Moscow", timeoutSeconds: 300, memory: "256MiB" }, async () => {
  const today = mskDayKey();
  const plan = new Map(); // uid → { course: {next}, challenges: [{c, others}] }
  const entry = (uid) => {
    if (!plan.has(uid)) plan.set(uid, { course: null, challenges: [] });
    return plan.get(uid);
  };

  const courseSnap = await db.collection("users").where("course.active", "==", true).get();
  const userDocs = new Map();
  for (const doc of courseSnap.docs) {
    const d = doc.data();
    userDocs.set(doc.id, d);
    const next = courseNextDay(d.course, today);
    if (!next) continue;
    if (next > COURSE_FREE_DAYS && !isProActive(d)) continue;
    entry(doc.id).course = { next };
  }

  // Челленджи: стартовали за последние 30 дней (самый длинный свой челлендж); завершённые отсеиваем.
  const minStart = new Date((dayKeyToIndex(today) - 29) * DAY_MS).toISOString().slice(0, 10);
  const chSnap = await db.collection("challenges").where("startKey", ">=", minStart).get();
  for (const doc of chSnap.docs) {
    const c = doc.data();
    const dayNum = dayKeyToIndex(today) - dayKeyToIndex(c.startKey) + 1;
    if (dayNum < 1 || dayNum > (c.days || CHALLENGE_DAYS)) continue;
    for (const m of c.members || []) {
      if (((c.checkins && c.checkins[m]) || []).includes(today)) continue;
      const others = (c.members || []).filter((x) => x !== m && ((c.checkins && c.checkins[x]) || []).includes(today)).length;
      entry(m).challenges.push({ id: doc.id, c, others });
    }
  }

  let sent = 0;
  for (const [uid, p] of plan) {
    try {
      let d = userDocs.get(uid);
      if (!d) {
        const snap = await db.collection("users").doc(uid).get();
        if (!snap.exists) continue;
        d = snap.data();
      }
      if (d.programRemindersOff === true) continue;
      const ch = p.challenges;
      let title;
      let body;
      let data;
      if (p.course && ch.length) {
        title = `Урок ${p.course.next} из 30 и челлендж ждут тебя 🌸`;
        body = `${COURSE_TITLES[p.course.next - 1]} — и не забудь отметиться в «${ch[0].c.title}»`;
        data = { type: "course" };
      } else if (p.course) {
        title = `Урок ${p.course.next} из 30 ждёт тебя 🌸`;
        body = `${COURSE_TITLES[p.course.next - 1]} — 3 минуты на заботу о себе`;
        data = { type: "course" };
      } else if (ch.length === 1) {
        const x = ch[0];
        title = `${x.c.emoji} ${x.c.title}`;
        body = x.others ? `Подруги уже отметились (${x.others}) — твоя очередь 💪` : "Отметь сегодняшний день, пока он не закончился 💪";
        data = { type: "challenge", id: x.id };
      } else if (ch.length > 1) {
        title = "Челленджи ждут отметки 💪";
        body = `Сегодня ещё не отмечено: ${ch.map((x) => `${x.c.emoji} ${x.c.title}`).join(", ")}`.slice(0, 180);
        data = { type: "challenge" };
      } else continue;
      await sendPush(uid, title, body, data);
      sent++;
    } catch (e) {
      console.error("[courseReminder]", uid, e && e.message);
    }
  }
  if (sent) console.log(`[courseReminder] sent ${sent}`);
});

// ==========================================
// 18. АНАЛИЗ КОЖИ ПО ФОТО (v2.0)
// ==========================================
// Только с согласия (users.skinConsentAt). Фото не сохраняется: анализ в памяти, в базу пишется
// только текстовый результат (users/{uid}/skin_checks) — для истории и прогресса.
// Косметическая оценка, не диагноз; родинки и новообразования не оцениваем.

const SKIN_PROMPT = `Ты — косметолог. На фото — лицо пользовательницы, которая сама попросила оценить состояние кожи для подбора ухода.
Оцени ТОЛЬКО видимое состояние кожи. Верни ТОЛЬКО JSON:
{
 "ok": true,
 "quality": "good" | "fair",
 "qualityTip": "если fair — что улучшить в следующем фото (свет, макияж, ракурс), иначе пусто",
 "skinType": "сухая" | "нормальная" | "комбинированная" | "жирная",
 "sensitivity": true | false,
 "summary": "2 тёплых предложения: общее впечатление и главное, на чём сосредоточиться",
 "concerns": [{"key": "breakouts|redness|dryness|oiliness|pores|pigmentation|dullness|fine_lines|dark_circles|texture", "name": "по-русски", "level": 1|2|3, "zone": "где видно: лоб, Т-зона, щёки, подбородок…", "tip": "что делать, 1 предложение"}],
 "strengths": ["1–3 сильные стороны кожи"],
 "morning": ["3–5 шагов утреннего ухода: тип средства и ключевые компоненты, без брендов"],
 "evening": ["3–5 шагов вечернего ухода"],
 "weekly": ["0–2 процедуры раз в неделю"],
 "avoid": ["0–3 чего избегать"],
 "phaseTip": "1 предложение про уход в её текущую фазу цикла из досье (или пусто)",
 "seeDoctor": false,
 "seeDoctorReason": ""
}
ПРАВИЛА:
- Обращайся на «ты», в женском роде («используй», «выбирай», «тебе подойдёт»), тепло и просто, как подруга-косметолог.
- Только простые слова, без профессиональных терминов. Вместо «тургор» — «упругость», «периорбитальная область» — «под глазами», «ПАВ» — «моющие компоненты», «некомедогенный» — «не забивает поры», «себорегулирующий» — «уменьшает жирность». zone — тоже простыми словами: лоб, нос, щёки, подбородок, под глазами.
- name в concerns — с заглавной буквы.
- Это косметическая оценка, НЕ диагноз. Не называй болезней (акне, розацеа, дерматит, мелазма и т.п.) — описывай видимое: «высыпания», «покраснения», «шелушение», «пигментные пятна».
- НЕ оценивай родинки, пятна неясного происхождения и новообразования. Если видишь заметные воспаления, язвочки, сильное раздражение или что-то, что требует врача, — "seeDoctor": true и мягкая причина ("Есть воспаления, которые лучше показать дерматологу").
- Не комментируй внешность, привлекательность, возраст «на вид», вес, национальность. Не пытайся узнать человека.
- level: 1 — слегка, 2 — заметно, 3 — выражено. До 5 concerns, только реально видимые. Если кожа в хорошем состоянии — это нормально, concerns может быть мало.
- Беременность в досье: никаких ретиноидов, высоких концентраций кислот, гидрохинона.
- Учитывай тип кожи из досье, если он указан, но доверяй фото.
- Если на фото нет лица, лицо слишком далеко, сильно размыто, в макияже, под фильтром или в тени так, что кожу не разглядеть — верни {"ok": false, "reason": "что не так и как переснять"}.`;

function cleanSkinJson(raw) {
  let j;
  try {
    j = JSON.parse(String(raw || "").replace(/^```(?:json)?\s*|\s*```$/g, ""));
  } catch (e) {
    return { ok: false, reason: "Не получилось разобрать фото. Попробуй ещё раз при дневном свете." };
  }
  if (!j || j.ok === false) return { ok: false, reason: String((j && j.reason) || "Не получилось оценить кожу на этом фото").slice(0, 240) };
  const str = (v, n = 240) => (v === null || v === undefined ? "" : String(v).slice(0, n));
  const arr = (v, n) => (Array.isArray(v) ? v.slice(0, n).map((x) => str(x, 160)).filter(Boolean) : []);
  const KEYS = ["breakouts", "redness", "dryness", "oiliness", "pores", "pigmentation", "dullness", "fine_lines", "dark_circles", "texture"];
  const types = ["сухая", "нормальная", "комбинированная", "жирная"];
  return {
    ok: true,
    quality: j.quality === "fair" ? "fair" : "good",
    qualityTip: str(j.qualityTip, 200),
    skinType: types.includes(j.skinType) ? j.skinType : "",
    sensitivity: j.sensitivity === true,
    summary: str(j.summary, 400),
    concerns: (Array.isArray(j.concerns) ? j.concerns : []).slice(0, 5).map((c) => ({
      key: KEYS.includes(c && c.key) ? c.key : "texture",
      name: str(c && c.name, 40),
      level: Math.min(3, Math.max(1, toInt(c && c.level, 1))),
      zone: str(c && c.zone, 60),
      tip: str(c && c.tip, 160),
    })).filter((c) => c.name),
    strengths: arr(j.strengths, 3),
    morning: arr(j.morning, 5),
    evening: arr(j.evening, 5),
    weekly: arr(j.weekly, 2),
    avoid: arr(j.avoid, 3),
    phaseTip: str(j.phaseTip, 200),
    seeDoctor: j.seeDoctor === true,
    seeDoctorReason: str(j.seeDoctorReason, 200),
  };
}

exports.skinAnalysis = onCall({ maxInstances: 20, timeoutSeconds: 90, memory: "512MiB" }, async (request) => {
  const uid = requireAuth(request);
  const p = request.data || {};
  const image = typeof p.imageBase64 === "string" ? p.imageBase64 : "";
  if (!image || image.length > 8 * 1024 * 1024) throw new HttpsError("invalid-argument", "Нет фото или оно слишком большое");
  const uSnap = await db.collection("users").doc(uid).get();
  if (!uSnap.exists || !uSnap.data().skinConsentAt) throw new HttpsError("failed-precondition", "Нужно согласие на обработку фото");

  const quota = await consumeQuota(uid, "scan");
  if (!quota.allowed) throw quota.limit ? new HttpsError("failed-precondition", PRO_LIMIT_TEXT) : new HttpsError("resource-exhausted", "QUOTA_EXCEEDED");
  try {
    const ctx = await scanContext(uid);
    const model = getGenAI().getGenerativeModel({
      model: VISION_MODEL,
      systemInstruction: `${SKIN_PROMPT}\n\nДОСЬЕ:\n${ctx}`,
      generationConfig: genConfig(VISION_MODEL, "low", { responseMimeType: "application/json" }),
    });
    const result = await generateWithRetry(() => model.generateContent(["Оцени состояние кожи на фото.", { inlineData: { data: image, mimeType: "image/jpeg" } }]));
    await trackUsage("skin_analysis", VISION_MODEL, geminiUsage(result));
    const out = cleanSkinJson(result && result.response && result.response.text());
    if (!out.ok) {
      await refundQuota(uid, quota); // неудачное фото не списываем
      return out;
    }
    const ref = await db.collection("users").doc(uid).collection("skin_checks").add({ ...out, at: FieldValue.serverTimestamp() });
    if (out.skinType) await db.collection("users").doc(uid).set({ skinType: out.skinType }, { merge: true });
    return { ...out, id: ref.id, at: Date.now() };
  } catch (e) {
    console.error("[skinAnalysis]", uid, e && e.message);
    await refundQuota(uid, quota);
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("unavailable", "Ева временно недоступна. Попробуй ещё раз.");
  }
});

// ==========================================
// 19. ГОЛОСОВАЯ ЕВА (v2.0)
// ==========================================
// transcribeVoice — голосовое сообщение → текст (Gemini понимает аудио напрямую). Аудио не сохраняется.
// speakText — озвучка ответа голосом Евы (Gemini TTS), только PRO, кэш в Storage по хэшу текста.

const TTS_MODEL = process.env.GEMINI_TTS_MODEL || "gemini-3.8-flash-tts";
const TTS_VOICE = process.env.GEMINI_TTS_VOICE || "Sulafat";
AI_PRICES[TTS_MODEL] = AI_PRICES[TTS_MODEL] || [1.0, 20.0, 0.1]; // оценка: точной цены 3.8 TTS в документации нет
PRO_DAILY_LIMITS.tts = 20;

exports.transcribeVoice = onCall({ maxInstances: 20, timeoutSeconds: 60, memory: "512MiB" }, async (request) => {
  const uid = requireAuth(request);
  const p = request.data || {};
  const audio = typeof p.audioBase64 === "string" ? p.audioBase64 : "";
  const mime = ["audio/wav", "audio/aac", "audio/mp4", "audio/ogg", "audio/mpeg"].includes(p.mime) ? p.mime : "audio/wav";
  if (!audio || audio.length > 4 * 1024 * 1024) throw new HttpsError("invalid-argument", "Слишком длинное голосовое (до 1 минуты)");
  const model = getGenAI().getGenerativeModel({
    model: TEXT_MODEL,
    systemInstruction: "Ты — распознаватель речи. Перепиши дословно, что говорит человек на аудио, на языке речи (обычно русский), с нормальной пунктуацией. Не отвечай на вопросы, не добавляй ничего от себя. Если речи нет или её не разобрать — верни пустую строку.",
    generationConfig: genConfig(TEXT_MODEL, "minimal"),
  });
  try {
    const result = await generateWithRetry(() => model.generateContent(["Распознай речь.", { inlineData: { data: audio, mimeType: mime } }]));
    await trackUsage("voice_transcribe", TEXT_MODEL, geminiUsage(result));
    const text = ((result && result.response && result.response.text()) || "").trim().replace(/^["«]|["»]$/g, "").slice(0, 2000);
    return { text };
  } catch (e) {
    console.error("[transcribeVoice]", uid, e && e.message);
    throw new HttpsError("unavailable", "Не получилось распознать голос. Попробуй ещё раз.");
  }
});

/** Текст ответа Евы → то, что можно прочитать вслух. */
function speakableText(raw) {
  let t = String(raw || "");
  t = t.replace(/```[\s\S]*?```/g, " ");
  t = t.replace(/\[SHOPPING_LIST\][\s\S]*?\[\/SHOPPING_LIST\]/g, " ");
  t = t.replace(/https?:\/\/\S+/g, " ");
  t = t.replace(/[*_#>`~|]/g, "");
  t = t.replace(/^\s*[-•]\s+/gm, "");
  t = t.replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]/gu, "");
  t = t.replace(/[ \t]+/g, " ").replace(/\n{2,}/g, "\n").trim();
  if (t.length > 900) {
    const cut = t.slice(0, 900);
    const end = Math.max(cut.lastIndexOf(". "), cut.lastIndexOf("! "), cut.lastIndexOf("? "), cut.lastIndexOf("\n"));
    t = (end > 300 ? cut.slice(0, end + 1) : cut) + " Остальное — в тексте сообщения.";
  }
  return t;
}

exports.speakText = onCall({ maxInstances: 20, timeoutSeconds: 120, memory: "512MiB" }, async (request) => {
  const uid = requireAuth(request);
  const text = speakableText((request.data || {}).text);
  if (text.length < 2) throw new HttpsError("invalid-argument", "Нечего озвучить");
  const uSnap = await db.collection("users").doc(uid).get();
  if (!isProActive(uSnap.exists ? uSnap.data() : {})) throw new HttpsError("failed-precondition", "PRO_REQUIRED");

  const hash = require("crypto").createHash("sha1").update(`${TTS_MODEL}|${TTS_VOICE}|${text}`).digest("hex");
  const file = getStorage().bucket().file(`tts_cache/${hash}.wav`);
  try {
    const [exists] = await file.exists();
    if (exists) {
      const [buf] = await file.download();
      return { audioBase64: buf.toString("base64"), mime: "audio/wav", cached: true };
    }
  } catch (e) {
    console.warn("[speakText] cache read:", e && e.message);
  }

  // Длинный ответ клиент озвучивает частями (первая часть короткая — звук начинается быстрее).
  // Лимит считаем по ответам: списываем только за первую часть.
  const part = toInt((request.data || {}).part, 0);
  const quota = part > 0 ? { allowed: true, pro: true } : await consumeQuota(uid, "tts");
  if (!quota.allowed) throw new HttpsError("failed-precondition", "Сегодня Ева уже много говорила голосом 💗 Озвучка снова будет доступна завтра.");
  try {
    const res = await fetch("https://generativelanguage.googleapis.com/v1beta/interactions", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey.value() },
      body: JSON.stringify({
        model: TTS_MODEL,
        input: [{ type: "user_input", content: [{ type: "text", text, annotations: [{ type: "speech_metadata", style: "warm, calm and caring, like a close friend" }] }] }],
        response_format: { type: "audio" },
        generation_config: { speech_config: [{ voice: TTS_VOICE }] },
      }),
      signal: AbortSignal.timeout(100000),
    });
    if (!res.ok) throw new Error(`tts ${res.status}: ${(await res.text()).slice(0, 300)}`);
    const j = await res.json();
    const audios = [];
    for (const step of j.steps || []) {
      if (step.type !== "model_output") continue;
      for (const c of step.content || []) if (c.type === "audio" && c.data) audios.push(c.data);
    }
    const b64 = audios[audios.length - 1] || (j.output_audio && j.output_audio.data);
    if (!b64) throw new Error("tts: no audio in response");
    const buf = Buffer.from(b64, "base64");
    // Оценка токенов: ~25 аудиотокенов в секунду (WAV 24 кГц, 16 бит, моно = 48 000 байт/с).
    await trackUsage("tts", TTS_MODEL, { in: Math.ceil(text.length / 4), out: Math.ceil((buf.length / 48000) * 25), cached: 0 });
    file.save(buf, { contentType: "audio/wav", resumable: false }).catch((e) => console.warn("[speakText] cache save:", e && e.message));
    return { audioBase64: b64, mime: "audio/wav", cached: false };
  } catch (e) {
    console.error("[speakText]", uid, e && e.message);
    await refundQuota(uid, quota);
    throw new HttpsError("unavailable", "Не получилось озвучить. Попробуй ещё раз.");
  }
});
