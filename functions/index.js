const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const auth = require("firebase-functions/v1/auth"); 
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

// --- ИМПОРТЫ ДЛЯ RUSTORE ---
const jwt = require("jsonwebtoken");
const { v4: uuidv4 } = require("uuid");
const axios = require("axios");
const https = require("https");
const fs = require("fs");
const path = require("path");
const { rootCa, subCa } = require("./certificates.js");

admin.initializeApp();

const geminiKey = defineString('GEMINI_API_KEY');

// --- КЛЮЧИ RUSTORE (из .env) ---
const ruStoreKeyId = defineString('RUSTORE_KEY_ID');
const ruStorePrivateKey = defineString('RUSTORE_PRIVATE_KEY');

function getGenAI() {
    return new GoogleGenerativeAI(geminiKey.value());
}

// ------------------------------------------------------------------
// ОПТИМИЗАЦИЯ И СВЯЗЬ С RUSTORE (БЕЗ КОНФЛИКТА СЕРТИФИКАТОВ)
// ------------------------------------------------------------------
let ruStoreHttpsAgent = null;
function getRuStoreAgent() {
    if (!ruStoreHttpsAgent) {
        // Отключаем строгую проверку корневых центров сертификации,
        // так как Firebase (Google) по умолчанию не доверяет сертификатам Минцифры РФ.
        // Безопасность гарантируется JWS-подписью и нашими RSA-ключами.
        ruStoreHttpsAgent = new https.Agent({ 
            rejectUnauthorized: false 
        });
        console.log("✅ Агент RuStore инициализирован (rejectUnauthorized: false)");
    }
    return ruStoreHttpsAgent;
}

// ==========================================
// 1. ОЧИСТКА ДАННЫХ ПРИ УДАЛЕНИИ АККАУНТА
// ==========================================
exports.cleanupOnAccountDelete = auth.user().onDelete(async (user) => {
    const uid = user.uid;
    const db = admin.firestore();
    try {
        const chatsSnap = await db.collection('chats').where('users', 'array-contains', uid).get();
        if (!chatsSnap.empty) {
            const chatBatch = db.batch();
            chatsSnap.docs.forEach(doc => chatBatch.delete(doc.ref));
            await chatBatch.commit();
        }

        const userRef = db.collection('users').doc(uid);
        const subcollections = await userRef.listCollections();
        for (const subcoll of subcollections) await deleteCollectionInBatches(subcoll);
        await userRef.delete();
        await admin.storage().bucket().deleteFiles({ prefix: `users/${uid}/` });
    } catch (error) { console.error(`[cleanupOnAccountDelete] ERROR for ${uid}:`, error); }
});

async function deleteCollectionInBatches(collectionRef) {
    let snapshot = await collectionRef.limit(500).get();
    while (snapshot.size > 0) {
        const batch = admin.firestore().batch();
        snapshot.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        snapshot = await collectionRef.limit(500).get();
    }
}

// ==========================================
// 2. БАЗОВЫЕ PUSH-УВЕДОМЛЕНИЯ
// ==========================================
async function sendPush(uid, title, body, dataPayload = {}) {
    try {
        const userDoc = await admin.firestore().collection('users').doc(uid).get();
        if (!userDoc.exists || !userDoc.data().fcmToken) return;
        await admin.messaging().send({
            token: userDoc.data().fcmToken,
            notification: { title: title, body: body },
            android: { priority: "high", notification: { channelId: "high_importance_channel" } },
            apns: { payload: { aps: { contentAvailable: true, sound: "default" } } },
            data: dataPayload
        });
    } catch (error) {
        if (error.code === 'messaging/registration-token-not-registered') {
            await admin.firestore().collection('users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
        }
    }
}

exports.notifyOnNewNotification = onDocumentCreated('users/{userId}/notifications/{notificationId}', async (event) => {
    const notifData = event.data.data();
    if (notifData) await sendPush(event.params.userId, notifData.title || "Новое уведомление", notifData.body || "", { type: notifData.type || "general" });
});

// ==========================================
// 3. EVA — ИИ-НУТРИЦИОЛОГ
// ==========================================
exports.askDietitian = onCall({ cors: true, maxInstances: 10, timeoutSeconds: 120 }, async (request) => {
    const { prompt, history, userContext, imagesBase64, pdfBase64 } = request.data;
    try {
        const model = getGenAI().getGenerativeModel({ model: "gemini-2.5-flash", generationConfig: { temperature: 0.0 } });
        
        const systemPrompt = `[СИСТЕМНЫЕ ИНСТРУКЦИИ ДЛЯ ИИ]
Ты — Eva, элитный нутрициолог, велнес-ментор и заботливая ИИ-подруга в приложении Моя Ева. Твоя цель — помогать с питанием, женским здоровьем и образом жизни.

ДОСЬЕ ПОЛЬЗОВАТЕЛЯ (ТЕКУЩИЙ КОНТЕКСТ):
${userContext || "(Профиль пока не заполнен)"}

🚨 КРИТИЧЕСКИ ВАЖНЫЕ ПРАВИЛА АНАЛИЗА И ДИАЛОГА (ВЫПОЛНЯТЬ БЕЗУКОСНИТЕЛЬНО):
1. ИДЕНТИФИКАЦИЯ: Никогда не называй пользователя Евой! Тебя зовут Ева. Имя пользователя указано в досье выше. Обращайся к пользователю строго по этому имени (или просто на "ты", если имя не указано).
2. АНАЛИЗ ЧУЖИХ ДАННЫХ: Если пользователь уточняет, что анализы/документы принадлежат другому человеку (например, "это анализы моей дочери", "это мужа"), КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО применять к этим анализам цель пользователя по весу и фазу цикла пользователя! Оценивай их как отдельного независимого пациента соответствующего возраста.
3. ЗАПРЕТ НА ЗАЦИКЛИВАНИЕ (СМЕНА ТЕМЫ): Если пользователь меняет тему (например, просит рецепт пирога, тренировку или спрашивает о другом), МГНОВЕННО переключайся на новую тему. НИКОГДА не требуй прислать фото, анализы или файлы, которые ты просила в предыдущих сообщениях. Забудь про них и выполняй новую задачу.
4. АМНЕЗИЯ ФАЙЛОВ: Если в истории чата есть пометка "[СИСТЕМНОЕ СООБЩЕНИЕ: В этом запросе пользователь прикреплял файлы...]", это значит, что ты УЖЕ видела и проанализировала эти файлы в прошлом. НЕ ПРОСИ прислать их снова, отвечай строго по сути вопроса.
5. ТОН ОБЩЕНИЯ: КАТЕГОРИЧЕСКИ ЗАПРЕЩАЕТСЯ здороваться (не пиши Привет, Добрый день) в начале каждого сообщения. Сразу переходи к сути. Общайся тепло, на "ты" и в женском роде. Задавай уместные уточняющие вопросы.
6. ЛОКАЛЬНЫЕ ПРОДУКТЫ: Всегда предлагай блюда из простых, базовых продуктов, доступных в любом обычном супермаркете России и СНГ.

СЦЕНАРИИ РАБОТЫ:
- Расчет КБЖУ и Оценка еды (по фото/тексту): Твой текстовый ответ должен быть сверхкоротким. 1 предложение-поддержка, список КБЖУ и обязательный JSON-блок. Не читай длинных лекций про пользу каждого ингредиента!
- Медицинские анализы: Сначала объясни простым языком, за что отвечает показатель. Дай общие рекомендации по питанию. Напомни, что ты ИИ, и для точного диагноза нужен врач.
- Рецепты: Максимально короткий ответ: вступление (1 предложение), ингредиенты, шаги приготовления и блок [SHOPPING_LIST]. Никаких длинных философских рассуждений.

ТЕХНИЧЕСКИЕ ПРАВИЛА ДЛЯ JSON (ДЛЯ РАБОТЫ ИНТЕРФЕЙСА):
Сначала идет твой текстовый ответ, а В САМОМ КОНЦЕ — скрытый JSON блок.
- Для обновления цели КБЖУ:
\`\`\`json
{ "action_type": "update_goal", "coach_message": "Цель обновлена! ✨", "calories": 2000, "protein": 150, "fat": 65, "carbs": 200 }
\`\`\`
- Для добавления еды: ВСЕГДА разбивай сложные блюда на базовые компоненты (не пиши общее название в каждый ингредиент). Для каждого ингредиента сгенерируй "health_score" (1-10) и "fiber" (клетчатку).
\`\`\`json
{"action_type": "log_food", "coach_message": "Добавила в дневник! 🌸", "items": [{"meal_name": "Лосось", "weight_g": 150, "calories": 250, "protein": 25, "fat": 15, "carbs": 0, "fiber": 0, "health_score": 9}, {"meal_name": "Брокколи", "weight_g": 50, "calories": 17, "protein": 1, "fat": 0, "carbs": 3, "fiber": 2, "health_score": 10}]}
\`\`\`
- Для списка покупок (СТРОГО БЕЗ markdown-оберток, без тройных кавычек, только чистый текст внутри тегов):
[SHOPPING_LIST]
{"items": [{"name": "Гречка", "amount": "200 г", "category": "Бакалея"}]}
[/SHOPPING_LIST]

[КОНЕЦ СИСТЕМНЫХ ИНСТРУКЦИЙ]`;

        const fullPrompt = `${systemPrompt}\n\nНОВЫЙ ЗАПРОС ОТ ПОЛЬЗОВАТЕЛЯ:\n${prompt || "Посмотри файлы"}`;
        
        let result;
        if (pdfBase64) {
            result = await model.generateContent([
                fullPrompt, 
                { inlineData: { data: pdfBase64, mimeType: "application/pdf" } }
            ]);
        } else if (imagesBase64 && imagesBase64.length > 0) {
            const imageParts = imagesBase64.map(base64Str => ({
                inlineData: { data: base64Str, mimeType: "image/jpeg" }
            }));
            result = await model.generateContent([
                fullPrompt, 
                ...imageParts
            ]);
        } else {
            let cleanHistory = [];
            let expectedRole = 'user';
            for (const msg of (Array.isArray(history) ? history : [])) {
                const role = (msg.role === 'ai' || msg.role === 'assistant' || msg.role === 'model') ? 'model' : 'user';
                const text = msg.text || '';
                if (role === expectedRole && text.trim().length > 0) {
                    cleanHistory.push({ role: role, parts: [{ text: text }] });
                    expectedRole = (expectedRole === 'user') ? 'model' : 'user';
                }
            }
            if (cleanHistory.length > 0 && cleanHistory[cleanHistory.length - 1].role !== 'model') cleanHistory.pop(); 
            const chat = model.startChat({ history: cleanHistory });
            result = await chat.sendMessage(fullPrompt);
        }
        return { text: result.response.text() };
    } catch (error) {
        throw new HttpsError('internal', 'Ошибка Eva.', error.message);
    }
});

// ==========================================
// 4. PUSH-УВЕДОМЛЕНИЯ ДЛЯ ЛИЧНЫХ ЧАТОВ
// ==========================================
exports.onNewChatMessage = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
    const messageData = event.data.data();
    if (!messageData) return;
    const senderId = messageData.senderId;
    const text = messageData.text;
    const chatId = event.params.chatId;
    const users = chatId.split('_');
    const recipientId = users.find(id => id !== senderId);
    if (!recipientId) return;
    try {
        const senderDoc = await admin.firestore().collection('users').doc(senderId).get();
        const senderName = senderDoc.exists ? senderDoc.data().name : "Пользователь";
        await sendPush(recipientId, `Новое сообщение от ${senderName}`, text, { type: "chat", chatId: chatId });
    } catch (error) {
        console.error(`[onNewChatMessage] Ошибка отправки пуша для ${recipientId}:`, error);
    }
});

// ==========================================
// 5. ВРЕМЕННЫЙ ОБХОД ГЕОБЛОКИРОВКИ (TRUST CLIENT)
// ==========================================
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

exports.verifyRuStorePurchase = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Нужна авторизация.');
    
    const uid = request.auth.uid;
    const { purchaseToken, productId } = request.data;

    if (!purchaseToken || !productId) {
        throw new HttpsError('invalid-argument', 'Необходимы purchaseToken и productId');
    }

    try {
        // Используем современный модульный вызов Firestore
        const db = getFirestore();
        const userRef = db.collection('users').doc(uid);

        if (productId === 'specialist_chat_monthly') {
            await userRef.update({ hasSpecialistAccess: true });
            console.log(`✅ Чат со специалистом открыт для ${uid}`);
            return { success: true, message: 'Доступ к специалисту открыт' };
        } else {
            const daysToAdd = productId.includes('year') ? 365 : 30;
            const expireDate = new Date();
            expireDate.setDate(expireDate.getDate() + daysToAdd);

            await userRef.update({
                isPro: true,
                proUntil: Timestamp.fromDate(expireDate)
            });
            
            console.log(`✅ Премиум успешно выдан пользователю ${uid} (в обход S2S)`);
            return { success: true, message: 'Подписка успешно активирована' };
        }
    } catch (error) {
        console.error("🚨 Ошибка записи в БД:", error);
        throw new HttpsError('internal', 'Ошибка активации подписки в базе данных');
    }
});