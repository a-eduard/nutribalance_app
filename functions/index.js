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
const GEMINI_MODEL = "gemini-2.5-flash";
const FREE_LIMITS = { message: 5, scan: 3 };

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
      model: GEMINI_MODEL,
      systemInstruction: `${EVA_SYSTEM_PROMPT}${mode === "meal_plan" ? MEAL_PLAN_RULES : ""}\n\nДОСЬЕ ПОЛЬЗОВАТЕЛЯ (ТЕКУЩИЙ КОНТЕКСТ):\n${userContext || "(Профиль пока не заполнен)"}`,
      generationConfig: {
        temperature: hasFiles ? 0.1 : 0.4,
        // Gemini 2.5 Flash по умолчанию «размышляет» перед ответом — отсюда
        // ожидание 20–40 секунд. Для переписки и меню это не нужно, для фото и
        // анализов оставляем небольшой бюджет.
        thinkingConfig: { thinkingBudget: hasFiles ? 1024 : 0 },
      },
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
      model: GEMINI_MODEL,
      generationConfig: { temperature: 0.6, responseMimeType: "application/json" },
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
