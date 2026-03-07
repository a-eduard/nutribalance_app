const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const auth = require("firebase-functions/v1/auth"); 
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();
const geminiKey = defineString('GEMINI_API_KEY');

function getGenAI() {
    return new GoogleGenerativeAI(geminiKey.value());
}

// ==========================================
// 1. ОЧИСТКА ДАННЫХ ПРИ УДАЛЕНИИ АККАУНТА
// ==========================================
exports.cleanupOnAccountDelete = auth.user().onDelete(async (user) => {
    const uid = user.uid;
    console.log(`[cleanupOnAccountDelete] Cleaning up data for user ${uid}`);
    const db = admin.firestore();

    try {
        const userRef = db.collection('users').doc(uid);
        const subcollections = await userRef.listCollections();

        for (const subcoll of subcollections) {
            await deleteCollectionInBatches(subcoll);
        }

        await userRef.delete();
        
        const bucket = admin.storage().bucket();
        await bucket.deleteFiles({ prefix: `users/${uid}/` });

        console.log(`[cleanupOnAccountDelete] SUCCESS for ${uid}`);
    } catch (error) {
        console.error(`[cleanupOnAccountDelete] FATAL ERROR for ${uid}:`, error);
    }
});

async function deleteCollectionInBatches(collectionRef) {
    const batchSize = 500;
    let snapshot = await collectionRef.limit(batchSize).get();

    while (snapshot.size > 0) {
        const batch = admin.firestore().batch();
        snapshot.docs.forEach((doc) => {
            batch.delete(doc.ref);
        });
        await batch.commit();
        snapshot = await collectionRef.limit(batchSize).get();
    }
}

// ==========================================
// 2. БАЗОВЫЕ PUSH-УВЕДОМЛЕНИЯ
// ==========================================
async function sendPush(uid, title, body, dataPayload = {}) {
    try {
        const userDoc = await admin.firestore().collection('users').doc(uid).get();
        if (!userDoc.exists) return;
        
        const fcmToken = userDoc.data().fcmToken;
        if (!fcmToken) return;

        const message = {
            token: fcmToken,
            notification: { title: title, body: body },
            android: { priority: "high", notification: { channelId: "high_importance_channel" } },
            apns: { payload: { aps: { contentAvailable: true, sound: "default" } } },
            data: dataPayload
        };

        await admin.messaging().send(message);
    } catch (error) {
        console.error(`[sendPush] ERROR sending to ${uid}:`, error);
        if (error.code === 'messaging/registration-token-not-registered') {
            await admin.firestore().collection('users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
        }
    }
}

exports.notifyOnNewNotification = onDocumentCreated('users/{userId}/notifications/{notificationId}', async (event) => {
    const userId = event.params.userId;
    const notifData = event.data.data();
    if (!notifData) return;
    
    const title = notifData.title || "Новое уведомление";
    const body = notifData.body || "Проверьте приложение NutriBalance.";
    await sendPush(userId, title, body, { type: notifData.type || "general" });
});

// ==========================================
// 3. EVA — ИИ-НУТРИЦИОЛОГ (ЕДИНСТВЕННЫЙ БОТ)
// ==========================================
exports.askDietitian = onCall({ cors: true, maxInstances: 10 }, async (request) => {
    const { prompt, history, userContext, imageBase64 } = request.data;
    
    try {
        const model = getGenAI().getGenerativeModel({ 
            model: "gemini-2.5-flash",
            generationConfig: { temperature: 0.2 }
        });
        
        const dietitianPrompt = `Ты — Eva, элитный нутрициолог и умный сканер продуктов приложения NutriBalance. Твоя цель: помогать девушкам достигать их целей комфортно и безопасно. Твой тон: поддерживающий, заботливый, профессиональный. Обращайся к пользователю в женском роде.

У тебя есть строго 4 сценария работы. В сценариях 1, 2 и 3 ты сначала согласовываешь действие текстом, и ТОЛЬКО после слова "Да/Сохрани" выдаешь блок \`\`\`json ... \`\`\`. 
Внутри JSON ВСЕГДА должно быть поле "action_type". Контекст клиента: ${userContext || ""}

СЦЕНАРИЙ 1: РАСЧЕТ ЦЕЛИ (КБЖУ) И ПЛАНА
Триггер: Пользователь просит рассчитать норму, похудеть и т.д.
Действие: Если нужных данных нет в контексте, задай 3 вопроса одним сообщением (параметры, активность, аллергии).
Только когда получишь ответы: рассчитай норму КБЖУ текстом и спроси: "Обновляем твою цель в профиле?"
JSON (только после согласия):
\`\`\`json
{
  "action_type": "update_goal",
  "coach_message": "Отлично, дорогая! Цель обновлена. Начинаем работу к фигуре мечты! ✨",
  "calories": 2000, "protein": 150, "fat": 65, "carbs": 200
}
\`\`\`

СЦЕНАРИЙ 2: ЗАПИСЬ ЕДЫ В ДНЕВНИК (Трекинг)
Действие: ОБЯЗАТЕЛЬНО разбивай разные продукты на отдельные элементы массива items. Рассчитай вес и КБЖУ для каждого. Спроси "Записать в дневник?"
JSON (только после согласия):
\`\`\`json
{
  "action_type": "log_food",
  "coach_message": "Добавила в твой дневник. Приятного аппетита! 🌸",
  "items": [
    {"meal_name": "Овсянка", "weight_g": 100, "calories": 350, "protein": 12, "fat": 6, "carbs": 60}
  ]
}
\`\`\`

СЦЕНАРИЙ 3: СОХРАНЕНИЕ ПРОДУКТА В БАЗУ (RAG)
Действие: Распознай КБЖУ строго на 100 грамм -> Напиши "Распознала продукт. Сохранить в нашу базу?"
JSON (только после согласия):
\`\`\`json
{
  "action_type": "save_to_rag",
  "coach_message": "Продукт успешно добавлен в твою базу!",
  "product_name": "Молоко", "calories_100g": 45, "protein_100g": 1, "fat_100g": 1.5, "carbs_100g": 6
}
\`\`\`

СЦЕНАРИЙ 4: ПРОСТАЯ КОНСУЛЬТАЦИЯ
Действие: Просто ответь текстом. НИКАКОГО JSON.

Запрос: ${prompt || ""}`;
        
        let result;
        if (imageBase64) {
            const imagePart = { inlineData: { data: imageBase64, mimeType: "image/jpeg" } };
            result = await model.generateContent([dietitianPrompt, imagePart]);
        } else {
            let cleanHistory = [];
            let rawHistory = Array.isArray(history) ? history : [];
            let expectedRole = 'user';
            
            for (const msg of rawHistory) {
                if (msg.role === expectedRole && msg.parts && msg.parts[0].text) {
                    cleanHistory.push(msg);
                    expectedRole = (expectedRole === 'user') ? 'model' : 'user';
                }
            }
            if (cleanHistory.length > 0 && cleanHistory[cleanHistory.length - 1].role !== 'model') {
                cleanHistory.pop(); 
            }
            
            const chat = model.startChat({ history: cleanHistory });
            result = await chat.sendMessage(dietitianPrompt);
        }
        
        return { text: result.response.text() };
    } catch (error) {
        console.error("Eva Error:", error);
        throw new HttpsError('internal', 'Ошибка Eva.', error.message);
    }
});