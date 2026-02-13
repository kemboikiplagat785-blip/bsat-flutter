const express = require('express');
const admin = require('firebase-admin');
const bodyParser = require('body-parser');

// Initialize Firebase Admin SDK
// You must download a service account JSON file from Firebase Console
// 1. Go to Firebase Console > Project Settings > Service Accounts
// 2. Click "Generate new private key"
// 3. Save it as "serviceAccountKey.json" in this folder.
try {
  const serviceAccount = require('./serviceAccountKey.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  console.log('Firebase Admin Initialized successfully.');
} catch (error) {
  console.error('ERROR: Could not load serviceAccountKey.json. Please download it from Firebase Console.');
  process.exit(1);
}

const app = express();
app.use(bodyParser.json());

app.post('/send', async (req, res) => {
    const { title, body, topic } = req.body;

    if (!title || !body) {
        return res.status(400).send('Missing title or body');
    }

    const message = {
        notification: {
            title: title,
            body: body
        },
        topic: topic || 'general'
    };

    try {
        const response = await admin.messaging().send(message);
        console.log('Successfully sent message:', response);
        res.status(200).send({ success: true, messageId: response });
    } catch (error) {
        console.log('Error sending message:', error);
        res.status(500).send({ success: false, error: error.message });
    }
});

const PORT = 3000;
app.listen(PORT, '0.0.0.0', () => { // Listen on all interfaces
    console.log(`Server is running on port ${PORT}`);
    console.log(`To connect from Android device via USB: Run "adb reverse tcp:3000 tcp:3000"`);
});
