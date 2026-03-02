// Импорты Firebase V2
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

// Инициализация Admin SDK
admin.initializeApp();

const GEMINI_API_KEY = "AIzaSyAO3okozzGjSqZOOLBD05fbkcErSWuACYg";
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);

// ==========================================
// ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ ДЛЯ ОТПРАВКИ ПУШЕЙ (ПРОБИВАЕТ СПЯЩИЙ РЕЖИМ)
// ==========================================
async function sendPush(uid, title, body, dataPayload = {}) {
    try {
        const userDoc = await admin.firestore().collection('users').doc(uid).get();
        if (!userDoc.exists) return;
        
        const fcmToken = userDoc.data().fcmToken;
        if (!fcmToken) {
            console.log(`У пользователя ${uid} нет fcmToken.`);
            return;
        }

        const message = {
            token: fcmToken,
            notification: {
                title: title,
                body: body
            },
            // Тот самый блок, который будит Android из Terminated State
            android: {
                priority: "high",
                notification: {
                    channelId: "high_importance_channel",
                    sound: "default"
                }
            },
            // Блок для пробуждения iOS
            apns: {
                payload: {
                    aps: {
                        contentAvailable: true,
                        sound: "default"
                    }
                }
            },
            data: dataPayload
        };

        const response = await admin.messaging().send(message);
        console.log(`Push успешно отправлен пользователю ${uid}:`, response);
    } catch (error) {
        console.error(`Ошибка при отправке push пользователю ${uid}:`, error);
        // Если токен протух или удален с устройства, зачищаем его в базе
        if (error.code === 'messaging/registration-token-not-registered' || error.code === 'messaging/invalid-registration-token') {
            await admin.firestore().collection('users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
            console.log(`Невалидный токен удален у пользователя ${uid}`);
        }
    }
}

// ==========================================
// ТРИГГЕРЫ PUSH-УВЕДОМЛЕНИЙ
// ==========================================

// 1. Новое сообщение в чате
exports.notifyOnNewChatMessage = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
    const msgData = event.data.data();
    const senderId = msgData.senderId;
    const text = msgData.text || "Отправил(а) медиафайл";
    
    // Получаем документ чата, чтобы узнать, кто второй участник
    const chatDoc = await admin.firestore().collection('chats').doc(event.params.chatId).get();
    if (!chatDoc.exists) return;
    
    const users = chatDoc.data().users || [];
    const receiverId = users.find(id => id !== senderId);
    if (!receiverId) return;

    // Узнаем имя отправителя
    const senderDoc = await admin.firestore().collection('users').doc(senderId).get();
    const senderName = senderDoc.exists ? (senderDoc.data().name || "Пользователь") : "Пользователь";

    await sendPush(receiverId, `Новое сообщение от ${senderName}`, text, { type: "chat", chatId: event.params.chatId });
});

// 2. Тренер отправил новую программу
exports.notifyOnNewWorkoutAssigned = onDocumentCreated('users/{userId}/assigned_workouts/{workoutId}', async (event) => {
    const athleteId = event.params.userId;
    const workoutData = event.data.data();
    const workoutName = workoutData.name || "Новая тренировка";
    
    await sendPush(athleteId, "Новая программа! 🎯", `Тренер прислал вам план: ${workoutName}`, { type: "workout" });
});

// 3. Спортсмен подал заявку тренеру
exports.notifyCoachOnNewRequest = onDocumentCreated('users/{coachId}/athlete_requests/{athleteId}', async (event) => {
    const coachId = event.params.coachId;
    const athleteId = event.params.athleteId;

    // Узнаем имя спортсмена
    const athleteDoc = await admin.firestore().collection('users').doc(athleteId).get();
    const athleteName = athleteDoc.exists ? (athleteDoc.data().name || "Спортсмен") : "Спортсмен";

    await sendPush(coachId, "Новая заявка! 🔥", `${athleteName} хочет с вами работать. Проверьте профиль.`, { type: "request" });
});

// 4. Тренер принял заявку
exports.notifyAthleteOnRequestAccepted = onDocumentUpdated('users/{coachId}/athlete_requests/{athleteId}', async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    
    // Проверяем, что статус изменился именно на accepted
    if (before.status === 'pending' && after.status === 'accepted') {
        const athleteId = event.params.athleteId;
        const coachId = event.params.coachId;

        // Узнаем имя тренера
        const coachDoc = await admin.firestore().collection('coaches').doc(coachId).get();
        const coachName = coachDoc.exists ? (coachDoc.data().name || "Тренер") : "Тренер";

        await sendPush(athleteId, "Заявка принята! 💪", `${coachName} подтвердил сотрудничество. Можете начинать работу!`, { type: "accepted" });
    }
});

// ==========================================
// ФУНКЦИИ ИИ (Без изменений)
// ==========================================

exports.generateTrainerWorkout = onCall({ cors: true, maxInstances: 10 }, async (request) => {
    const { prompt, history } = request.data;
    if (!prompt) throw new HttpsError('invalid-argument', 'Отсутствует prompt');
    
    try {
        const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
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
        const result = await chat.sendMessage(prompt);
        return { result: result.response.text() };
    } catch (error) {
        console.error("Trainer Error:", error);
        throw new HttpsError('internal', 'Ошибка Тренера.', error.message);
    }
});

exports.askDietitian = onCall({ cors: true, maxInstances: 10 }, async (request) => {
    const { prompt, history, userContext, imageBase64 } = request.data;
    
    try {
        const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
        
        const dietitianPrompt = `Ты — ИИ-Диетолог приложения Tonna AI. Контекст клиента: ${userContext || ""}
Твои задачи:
1. Создание плана: Если клиент хочет похудеть/набрать массу, спроси данные и рассчитай КБЖУ.
2. Трекинг еды: Оцени КБЖУ порции и ОБЯЗАТЕЛЬНО спроси: "Записать этот прием пищи в дневник?".
3. БРЕНДЫ И ПАМЯТЬ: Если пользователь указывает бренд, которого нет в контексте, считай по средним и проси этикетку.
4. АВТО-ПЕРЕРАСЧЕТ ПО ЭТИКЕТКЕ (ВАЖНО!): Если пользователь прислал фото этикетки для уточнения КБЖУ, ты должен не только учесть это, но и МГНОВЕННО выдать новую интерактивную карточку приема пищи (блок JSON формата "log_meal") с уже обновленными, точными цифрами. Пользователь должен мочь сразу нажать "Сохранить в базу".
5. ЗАПОМИНАНИЕ ПРОДУКТА: Если пользователь ПРЯМО просит просто "запомнить продукт на будущее" (без привязки к текущему приему пищи), выдавай JSON формата "save_food".
6. АНТИ-СПАМ ПРИВЕТСТВИЯМИ (КРИТИЧЕСКИ ВАЖНО): НИКОГДА не здоровайся с пользователем (не говори Привет, Здравствуйте, Добрый день и т.д.), если это не самое первое сообщение в истории чата. Отвечай сразу по делу.

Формат JSON для сохранения цели:
\`\`\`json
{ "type": "set_goal", "calories": 2000, "protein": 150, "fat": 70, "carbs": 200 }
\`\`\`
Формат JSON для записи еды (Авто-перерасчет):
\`\`\`json
{ "type": "log_meal", "meal_name": "Название блюда", "calories": 400, "protein": 30, "fat": 15, "carbs": 50 }
\`\`\`
Формат JSON для запоминания в личную базу (Память):
\`\`\`json
{ "type": "save_food", "name": "Название продукта", "calories": 110, "protein": 21, "fat": 2.5, "carbs": 0, "coach_message": "Отлично, я подготовил карточку продукта. Сохраняем в твою базу?" }
\`\`\`

Запрос клиента: ${prompt || ""}`;
        
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
        console.error("Dietitian Error:", error);
        throw new HttpsError('internal', 'Ошибка Нутрициолога.', error.message);
    }
});

exports.askCoachMentor = onCall({ cors: true, maxInstances: 10 }, async (request) => {
    const { prompt, history } = request.data;
    if (!prompt) throw new HttpsError('invalid-argument', 'Отсутствует prompt');
    
    try {
        const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
        const mentorPrompt = `Ты — профессиональный ментор для фитнес-тренеров, эксперт по биомеханике, реабилитации, чтению анализов и спортивной диетологии. 
Твоя цель: помогать тренеру разбирать сложные случаи его клиентов. Отвечай экспертно, профессиональным терминологическим языком. Не давай базовых советов, если тебя не просят.
АНТИ-СПАМ ПРИВЕТСТВИЯМИ (КРИТИЧЕСКИ ВАЖНО): НИКОГДА не здоровайся с пользователем (не пиши Привет, Здравствуйте и т.д.), если это не самое первое сообщение в чате. Отвечай сразу по делу.
Запрос тренера: ${prompt}`;
        
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
        const result = await chat.sendMessage(mentorPrompt);
        
        return { text: result.response.text() };
    } catch (error) {
        console.error("Mentor Error:", error);
        throw new HttpsError('internal', 'Ошибка ИИ-Ментора.', error.message);
    }
});