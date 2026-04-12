const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineString } = require("firebase-functions/params");
const auth = require("firebase-functions/v1/auth"); 
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const crypto = require("crypto"); // Для ключей идемпотентности ЮKassa

admin.initializeApp();

const geminiKey = defineString('GEMINI_API_KEY');
// Ключи ЮKassa из твоего файла .env
const yooShopId = defineString('YOOKASSA_SHOP_ID');
const yooSecretKey = defineString('YOOKASSA_SECRET_KEY');

function getGenAI() {
    return new GoogleGenerativeAI(geminiKey.value());
}

// ==========================================
// 1. ПЛАТЕЖИ ЮKASSA
// ==========================================

// 1.1 СОЗДАНИЕ ПЛАТЕЖА (Вызывается из Flutter)
exports.createPayment = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Нужна авторизация.');

    const uid = request.auth.uid;
    const userEmail = request.auth.token.email || 'no-reply@myeva.ru'; 
    
    // ФИКС 3: Идемпотентность теперь генерируется на клиенте (защита от двойных списаний)
    const { amount, description, paymentType, durationDays, idempotencyKey } = request.data;
    if (!idempotencyKey) throw new HttpsError('invalid-argument', 'Отсутствует ключ идемпотентности');

    const authString = Buffer.from(`${yooShopId.value()}:${yooSecretKey.value()}`).toString('base64');
    const formattedAmount = Number(amount).toFixed(2);

    try {
        const response = await fetch('https://api.yookassa.ru/v3/payments', {
            method: 'POST',
            headers: {
                'Authorization': `Basic ${authString}`,
                'Idempotence-Key': idempotencyKey, 
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                amount: { value: formattedAmount, currency: "RUB" },
                capture: true,
                confirmation: { type: "redirect", return_url: "https://myeva.ru/success" },
                description: description,
                receipt: {
                    customer: { email: userEmail },
                    items: [
                        {
                            // УЛУЧШЕНИЕ 1: Строгое описание для ФНС
                            description: "Оплата информационных услуг MyEva", 
                            quantity: "1.00",
                            amount: { value: formattedAmount, currency: "RUB" },
                            vat_code: 1, 
                            payment_mode: "full_prepayment", 
                            payment_subject: "service" 
                        }
                    ]
                },
                metadata: {
                    userId: uid,
                    paymentType: paymentType || 'premium',
                    durationDays: durationDays ? durationDays.toString() : '30'
                }
            })
        });

        const paymentData = await response.json();
        if (!response.ok) throw new HttpsError('invalid-argument', `ЮKassa отказала: ${paymentData.description || 'Неизвестная ошибка'}`);

        return { paymentId: paymentData.id, confirmationUrl: paymentData.confirmation.confirmation_url };
    } catch (error) {
        console.error("🔥 Ошибка createPayment:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', `Сбой сервера: ${error.message}`);
    }
});

// 1.2 WEBHOOK (Слушает ЮKassa и выдает доступ)
exports.yookassaWebhook = onRequest(async (req, res) => {
    // ФИКС 1: Базовая защита вебхука. ЮKassa шлет только POST.
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
    
    // Идеально: добавь в ЛК ЮKassa к URL вебхука ?secret=ТВОЙ_ПАРОЛЬ и раскомментируй строку ниже:
    // if (req.query.secret !== 'super_secret_code_123') return res.status(403).send('Forbidden');

    const event = req.body;

    if (event && event.event === 'payment.succeeded') {
        const paymentObj = event.object;
        const uid = paymentObj.metadata?.userId;
        const pType = paymentObj.metadata?.paymentType; 
        const durationDays = parseInt(paymentObj.metadata?.durationDays || '30', 10);

        if (uid) {
            try {
                const db = admin.firestore();
                const userRef = db.collection('users').doc(uid);
                
                if (pType === 'specialist') {
                    await userRef.update({ hasSpecialistAccess: true });
                } else {
                    // ФИКС 2: Честное накопление дней подписки
                    await db.runTransaction(async (t) => {
                        const doc = await t.get(userRef);
                        const data = doc.data() || {};
                        
                        let currentProUntil = data.proUntil ? data.proUntil.toDate() : new Date();
                        // Если подписка уже истекла, считаем от сегодня
                        if (currentProUntil < new Date()) {
                            currentProUntil = new Date();
                        }
                        
                        currentProUntil.setDate(currentProUntil.getDate() + durationDays);
                        
                        t.update(userRef, {
                            isPro: true,
                            proUntil: admin.firestore.Timestamp.fromDate(currentProUntil)
                        });
                    });
                }
                console.log(`✅ Доступ выдан юзеру ${uid} за платеж ${paymentObj.id}`);
            } catch (error) {
                console.error("Ошибка выдачи доступа:", error);
            }
        }
    }
    res.status(200).send('OK');
});

// ==========================================
// 2. ОЧИСТКА ДАННЫХ ПРИ УДАЛЕНИИ АККАУНТА
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
// 3. БАЗОВЫЕ PUSH-УВЕДОМЛЕНИЯ
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
// 4. EVA — ИИ-НУТРИЦИОЛОГ
// ==========================================
exports.askDietitian = onCall({ cors: true, maxInstances: 10, timeoutSeconds: 40 }, async (request) => {
    const { prompt, history, userContext, imagesBase64, pdfBase64 } = request.data;
    try {
        // Температура 0.0 заставит ИИ считать калории максимально точно и одинаково для одних и тех же фото
        const model = getGenAI().getGenerativeModel({ model: "gemini-2.5-flash", generationConfig: { temperature: 0.0 } });
        let dietitianPrompt = `Ты — Eva, элитный нутрициолог, велнес-ментор и заботливая ИИ-подруга в приложении MyEva. Твоя цель — стать лучшей и самой умной подругой для пользователя, помогая с питанием, женским здоровьем и образом жизни.
ДОСЬЕ ПОЛЬЗОВАТЕЛЯ (Внимательно изучи перед ответом):
${userContext || "(Профиль пока не заполнен)"}
ТВОЙ ХАРАКТЕР И ТОН ОБЩЕНИЯ:
- Общайся тепло, с эмпатией и заботой. Обращайся на "ты" и строго в женском роде.
- Ты не просто робот-калькулятор, ты подруга. Задавай уточняющие вопросы ("Как ты спишь?", "Как оцениваешь свой стресс?").
- Используй уместные эмодзи, форматируй текст списками и жирным шрифтом для удобства чтения.
ВАЖНОЕ ПРАВИЛО ОБЩЕНИЯ: Вы с пользователем ведете непрерывный диалог в формате мессенджера. КАТЕГОРИЧЕСКИ ЗАПРЕЩАЕТСЯ здороваться (не используй слова Привет, Здравствуй, Добрый день и т.д.) в своих ответах. Сразу переходи к сути вопроса. Используй имя пользователя для персонализации, но без формальных приветствий.
ПОВЕДЕНЧЕСКИЕ СЦЕНАРИИ (СТРОГО СОБЛЮДАТЬ):
Сценарий 1 (Первое касание и Онбординг):
Когда пользователь пишет первое сообщение или присылает первое фото еды, ты ДОЛЖНА пройти строго по этой цепочке в ОДНОМ сообщении:
Шаг 1: Дать ответ на запрос (например, посчитать калории на фото).
Шаг 2: Спросить: "Хочешь, я коротко расскажу, что еще я умею делать для тебя?".
Шаг 3: Напомнить: "А когда будет минутка, загляни в Профиль и пройди опрос, чтобы наши советы стали на 100% персональными!".
Сценарий 2: Расчет КБЖУ (Математика)
- Считай норму ТОЛЬКО по формуле Миффлина-Сан Жеора, учитывая активность. Объясни пользователю, откуда взялись эти цифры. Не завышай калории, если цель — похудение (делай дефицит 15-20%).
ПРАВИЛО ДЛЯ ОЦЕНКИ БЛЮД (ПО ФОТО ИЛИ ТЕКСТУ): Если пользователь присылает фото еды или просит посчитать КБЖУ блюда, твой текстовый ответ должен быть сверхкоротким.
Структура ответа строго такая:
1. Одно короткое предложение-комментарий или поддержка (например: 'Отличный выбор, говядина даст нужный белок!').
2. Краткий список КБЖУ (Калории, Белки, Жиры, Углеводы).
3. Обязательный JSON-блок для создания карточки 'Добавление в дневник'.
КАТЕГОРИЧЕСКИ ЗАПРЕЩАЕТСЯ: расписывать пользу каждого отдельного ингредиента (лаваша, овощей, мяса), писать длинные лекции про воду, фазы цикла или задавать вопросы в конце. Только КБЖУ и пара слов.
ПРАВИЛО ДЛЯ ОЦЕНКИ БЛЮД (ПО ФОТО ИЛИ ТЕКСТУ): Если пользователь присылает фото еды или просит посчитать КБЖУ блюда, твой текстовый ответ должен быть сверхкоротким.
Структура ответа строго такая:
1. Одно короткое предложение-комментарий или поддержка (например: 'Отличный выбор, говядина даст нужный белок!').
2. Краткий список КБЖУ (Калории, Белки, Жиры, Углеводы).
3. Обязательный JSON-блок для создания карточки 'Добавление в дневник'.
КАТЕГОРИЧЕСКИ ЗАПРЕЩАЕТСЯ: расписывать пользу каждого отдельного ингредиента (лаваша, овощей, мяса), писать длинные лекции про воду, фазы цикла или задавать вопросы в конце. Только КБЖУ и пара слов.
Сценарий 3: Анализ медицинских показателей (PDF/Фото)
- Внимательно прочитай анализы. Не отправляй к врачу сухой фразой!
- Сначала объясни простым языком, за что отвечает показатель.
- Дай рекомендации по питанию. Только в конце напомни, что ты ИИ, и для точного диагноза нужен врач.
Сценарий 4: Беременность
- Если в досье указано, что девушка беременна: рассказывай о плоде. Адаптируй советы по питанию для беременных.
Сценарий 5: Гармония (Стресс, Сон, Симптомы)
- Если девушка отмечает стресс, грусть или пониженный кальций/витамины: смести фокус с диет. Порекомендуй отдых, прогулки или ванну.
🚨 ТЕХНИЧЕСКИЕ ПРАВИЛА ДЛЯ ИНТЕРФЕЙСА ПРИЛОЖЕНИЯ (КРИТИЧЕСКИ ВАЖНО) 🚨
Сначала ты ДОЛЖНА подробно и заботливо текстом расписать КБЖУ и пользу блюда, похвалить пользователя, и ТОЛЬКО В САМОМ КОНЦЕ своего ответа выдать скрытый JSON.
Чтобы кнопки в приложении работали, ты ОБЯЗАНА использовать JSON-формат:
- Если договорились обновить цель КБЖУ:
\`\`\`json
{ "action_type": "update_goal", "coach_message": "Цель обновлена! ✨", "calories": 2000, "protein": 150, "fat": 65, "carbs": 200 }
\`\`\`
- Если пользователь хочет ЗАПИСАТЬ ЕДУ в дневник. КРИТИЧЕСКИ ВАЖНО: ВСЕГДА разбивай сложные блюда на ОТДЕЛЬНЫЕ базовые компоненты (например: булка, котлета, сыр, соус). НИКОГДА не дублируй общее название блюда в каждом элементе! Каждая строка должна быть отдельным логическим продуктом. В поле "meal_name" пиши НАЗВАНИЕ КОНКРЕТНОГО ИНГРЕДИЕНТА.
Для точного расчета калорий: используй стандарты USDA. Сначала оцени общий вес порции визуально (стандарт 250-300г), а затем распредели вес между ингредиентами пропорционально. Возвращай строго чистый JSON без markdown-оберток (\`\`\`json). 
Для каждого ингредиента сгенерируй "health_score" от 1 до 10 и "fiber" (клетчатка):
\`\`\`json
{"action_type": "log_food", "coach_message": "Добавила в дневник! 🌸", "items": [{"meal_name": "Стейк лосося с брокколи", "weight_g": 200, "calories": 320, "protein": 30, "fat": 20, "carbs": 5, "fiber": 4, "health_score": 9}]}
\`\`\`
- Если пользователь просит РЕЦЕПТ или список покупок:
ПРАВИЛО ДЛЯ РЕЦЕПТОВ: Твой ответ должен быть максимально коротким.
Структура ответа строго такая:
1. Короткое, дружелюбное вступление (максимум 1-2 предложения).
2. Список ингредиентов.
3. Короткие шаги приготовления.
4. Обязательный блок [SHOPPING_LIST] с JSON форматом для кнопки (как настроено ранее).
КАТЕГОРИЧЕСКИ ЗАПРЕЩАЕТСЯ писать длинные философские рассуждения о пользе продуктов до или после рецепта. Для медицинских анализов и других вопросов отвечай как обычно, это ограничение только для рецептов.
Пример скрытого тега:
[SHOPPING_LIST]{"items": [{"name": "Свекла", "amount": "2 шт", "category": "Овощи"}]}[/SHOPPING_LIST]`;
        dietitianPrompt += `\n\nЗапрос: ${prompt || ""}`;
        
        let result;
        if (pdfBase64) {
            result = await model.generateContent([
                dietitianPrompt, 
                { inlineData: { data: pdfBase64, mimeType: "application/pdf" } }
            ]);
        } else if (imagesBase64 && imagesBase64.length > 0) {
            const imageParts = imagesBase64.map(base64Str => ({
                inlineData: { data: base64Str, mimeType: "image/jpeg" }
            }));
            result = await model.generateContent([
                dietitianPrompt, 
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
            result = await chat.sendMessage(dietitianPrompt);
        }
        return { text: result.response.text() };
    } catch (error) {
        throw new HttpsError('internal', 'Ошибка Eva.', error.message);
    }
});

// ==========================================
// 5. PUSH-УВЕДОМЛЕНИЯ ДЛЯ ЛИЧНЫХ ЧАТОВ (COMMUNITY)
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
// 6. БЕЗОПАСНАЯ СЕРВЕРНАЯ ПРОВЕРКА ПОКУПОК RUSTORE
// ==========================================
exports.verifyRuStorePurchase = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Нужна авторизация.');
    
    const uid = request.auth.uid;
    const { purchaseToken, productId } = request.data;

    if (!purchaseToken || !productId) {
        throw new HttpsError('invalid-argument', 'Необходимы purchaseToken и productId');
    }

    // TODO: В будущем здесь будет реальный HTTP-запрос к RuStore API для валидации токена
    // https://public-api.rustore.ru/public/v3/subscription/subscriptions/{subscriptionToken}
    // Пока делаем базовую mock-проверку (перенесли логику с клиента на сервер)

    try {
        const db = admin.firestore();
        const userRef = db.collection('users').doc(uid);

        if (productId === 'specialist_chat_monthly') {
            await userRef.update({ hasSpecialistAccess: true });
            return { success: true, message: 'Доступ к специалисту открыт' };
        } else {
            let durationDays = 30; // По умолчанию месяц
            if (productId === 'eva_sub_1_year') durationDays = 365;

            // Используем транзакцию для безопасного накопления дней
            await db.runTransaction(async (t) => {
                const doc = await t.get(userRef);
                const data = doc.data() || {};

                let currentProUntil = data.proUntil ? data.proUntil.toDate() : new Date();
                
                // Если подписка уже истекла, считаем от сегодня
                if (currentProUntil < new Date()) {
                    currentProUntil = new Date();
                }
                
                currentProUntil.setDate(currentProUntil.getDate() + durationDays);

                t.update(userRef, {
                    isPro: true,
                    proUntil: admin.firestore.Timestamp.fromDate(currentProUntil)
                });
            });
            
            return { success: true, message: 'Подписка успешно активирована' };
        }
    } catch (error) {
        console.error("Ошибка верификации покупки RuStore:", error);
        throw new HttpsError('internal', 'Ошибка при обновлении базы данных');
    }
});