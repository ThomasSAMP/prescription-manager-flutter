const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
admin.initializeApp();

// Fonction qui s'exécute tous les jours à 8h du matin
exports.checkMedicationExpirations = functions
    .region('europe-west1') // Spécification de la région européenne
    .pubsub
    .schedule('0 8 * * *')  // Cron syntax: minute heure jour mois jour_semaine
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        // Calculer les dates limites pour les différents niveaux d'alerte
        const criticalDate = new Date();
        criticalDate.setDate(criticalDate.getDate() + 14); // 14 jours

        const warningDate = new Date();
        warningDate.setDate(warningDate.getDate() + 30); // 30 jours

        // Récupérer tous les médicaments qui arrivent à expiration
        const medicamentsSnapshot = await db.collection('medicaments')
            .where('expirationDate', '<=', admin.firestore.Timestamp.fromDate(warningDate))
            .get();

        if (medicamentsSnapshot.empty) {
            console.log('Aucun médicament n\'arrive à expiration');
            return null;
        }

        // Grouper les médicaments par niveau d'alerte
        const criticalMeds = [];
        const warningMeds = [];

        for (const doc of medicamentsSnapshot.docs) {
            const med = doc.data();
            med.id = doc.id;

            const expDate = med.expirationDate.toDate();

            if (expDate <= criticalDate) {
                criticalMeds.push(med);
            } else if (expDate <= warningDate) {
                warningMeds.push(med);
            }
        }

        // Créer les notifications dans Firestore
        const batch = db.batch();
        const notificationsRef = db.collection('notifications');

        // Notifications pour les médicaments critiques
        for (const med of criticalMeds) {
            const ordonnanceSnapshot = await db.collection('ordonnances').doc(med.ordonnanceId).get();
            const ordonnance = ordonnanceSnapshot.data();

            const notifRef = notificationsRef.doc();
            batch.set(notifRef, {
                title: 'Médicament bientôt expiré !',
                body: `Le médicament ${med.name} expire dans moins de 14 jours.`,
                type: 'expiration_critical',
                medicamentId: med.id,
                ordonnanceId: med.ordonnanceId,
                patientName: ordonnance.patientName,
                medicamentName: med.name,
                expirationDate: med.expirationDate,
                createdAt: now
            });
        }

        // Notifications pour les médicaments en alerte
        for (const med of warningMeds) {
            const ordonnanceSnapshot = await db.collection('ordonnances').doc(med.ordonnanceId).get();
            const ordonnance = ordonnanceSnapshot.data();

            const notifRef = notificationsRef.doc();
            batch.set(notifRef, {
                title: 'Attention à l\'expiration',
                body: `Le médicament ${med.name} expire dans moins de 30 jours.`,
                type: 'expiration_warning',
                medicamentId: med.id,
                ordonnanceId: med.ordonnanceId,
                patientName: ordonnance.patientName,
                medicamentName: med.name,
                expirationDate: med.expirationDate,
                createdAt: now
            });
        }

        await batch.commit();

        // Envoyer une notification push groupée
        if (criticalMeds.length > 0 || warningMeds.length > 0) {
            const totalCount = criticalMeds.length + warningMeds.length;

            const message = {
                notification: {
                    title: 'Médicaments arrivant à expiration',
                    body: `${totalCount} médicament(s) arrivent à expiration prochainement.`
                },
                data: {
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    screen: 'notifications'
                },
                topic: 'all_users' // Envoyer à tous les appareils abonnés à ce topic
            };

            await admin.messaging().send(message);
        }

        console.log(`Vérification terminée: ${criticalMeds.length} médicaments critiques, ${warningMeds.length} médicaments en alerte`);
        return null;
    });

// Fonction pour nettoyer les anciennes notifications (plus d'un mois)
exports.cleanupOldNotifications = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 0 * * 0')  // Tous les dimanches à minuit
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();

        // Calculer la date limite (un mois en arrière)
        const oneMonthAgo = new Date();
        oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1);

        // Récupérer les notifications plus anciennes qu'un mois
        const snapshot = await db.collection('notifications')
            .where('createdAt', '<', admin.firestore.Timestamp.fromDate(oneMonthAgo))
            .get();

        if (snapshot.empty) {
            console.log('Aucune notification ancienne à supprimer');
            return null;
        }

        // Supprimer les notifications anciennes
        const batch = db.batch();
        snapshot.docs.forEach(doc => {
            batch.delete(doc.ref);
        });

        await batch.commit();

        console.log(`${snapshot.size} notifications anciennes supprimées`);
        return null;
    });