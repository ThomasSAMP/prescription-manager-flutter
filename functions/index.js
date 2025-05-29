const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { MedicationState, DailyNotificationSummary } = require('./src/models');

admin.initializeApp();

// Fonction utilitaire pour déterminer le statut d'un médicament
function getMedicationStatus(expirationDate) {
    const now = new Date();
    const expDate = expirationDate.toDate();
    const diffInDays = Math.ceil((expDate - now) / (1000 * 60 * 60 * 24));

    if (diffInDays < 0) {
        return 'expired';
    } else if (diffInDays <= 14) {
        return 'critical';
    } else if (diffInDays <= 30) {
        return 'warning';
    } else {
        return 'ok';
    }
}

// Fonction pour créer le message de notification groupée
function createNotificationMessage(summary) {
    const lines = ['🏥 Prescription Manager'];

    if (summary.newExpiredCount > 0) {
        lines.push(`🚨 ${summary.newExpiredCount} médicament${summary.newExpiredCount > 1 ? 's' : ''} expiré${summary.newExpiredCount > 1 ? 's' : ''}`);
    }

    if (summary.newCriticalCount > 0) {
        lines.push(`⚠️ ${summary.newCriticalCount} médicament${summary.newCriticalCount > 1 ? 's' : ''} critique${summary.newCriticalCount > 1 ? 's' : ''}`);
    }

    if (summary.newWarningCount > 0) {
        lines.push(`🟡 ${summary.newWarningCount} médicament${summary.newWarningCount > 1 ? 's' : ''} en alerte`);
    }

    return {
        title: 'Prescription Manager',
        body: lines.slice(1).join('\n') // Exclure le titre de la première ligne
    };
}

// Fonction principale améliorée
exports.checkMedicationExpirations = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 8 * * *')
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();
        const today = new Date().toISOString().split('T')[0]; // Format YYYY-MM-DD

        console.log(`Starting medication expiration check for ${today}`);

        try {
            // 1. Récupérer tous les médicaments actuels
            const medicamentsSnapshot = await db.collection('medicaments').get();

            if (medicamentsSnapshot.empty) {
                console.log('No medications found');
                return null;
            }

            // 2. Récupérer les états précédents des médicaments
            const previousStatesSnapshot = await db.collection('medication_states').get();
            const previousStates = new Map();

            previousStatesSnapshot.docs.forEach(doc => {
                const state = MedicationState.fromFirestore(doc.data());
                previousStates.set(state.medicamentId, state);
            });

            // 3. Analyser les changements d'état
            const currentStates = new Map();
            const summary = new DailyNotificationSummary(today);

            for (const doc of medicamentsSnapshot.docs) {
                const medicament = doc.data();
                medicament.id = doc.id;

                // Récupérer les informations de l'ordonnance
                const ordonnanceDoc = await db.collection('ordonnances').doc(medicament.ordonnanceId).get();
                if (!ordonnanceDoc.exists) continue;

                const ordonnance = ordonnanceDoc.data();

                // Déterminer le statut actuel
                const currentStatus = getMedicationStatus(medicament.expirationDate);
                const previousState = previousStates.get(medicament.id);
                const previousStatus = previousState ? previousState.status : 'ok';

                // Créer l'état actuel
                const currentState = new MedicationState(
                    medicament.id,
                    medicament.ordonnanceId,
                    ordonnance.patientName,
                    medicament.name,
                    medicament.expirationDate,
                    currentStatus
                );

                currentStates.set(medicament.id, currentState);

                // Compter les totaux
                switch (currentStatus) {
                    case 'expired':
                        summary.totalExpiredCount++;
                        break;
                    case 'critical':
                        summary.totalCriticalCount++;
                        break;
                    case 'warning':
                        summary.totalWarningCount++;
                        break;
                }

                // Détecter les nouveaux changements d'état (vers un état plus critique)
                const statusPriority = { 'ok': 0, 'warning': 1, 'critical': 2, 'expired': 3 };

                if (statusPriority[currentStatus] > statusPriority[previousStatus]) {
                    // Nouveau changement vers un état plus critique
                    switch (currentStatus) {
                        case 'expired':
                            summary.newExpiredCount++;
                            break;
                        case 'critical':
                            summary.newCriticalCount++;
                            break;
                        case 'warning':
                            summary.newWarningCount++;
                            break;
                    }

                    summary.newMedications.push({
                        medicamentId: medicament.id,
                        ordonnanceId: medicament.ordonnanceId,
                        patientName: ordonnance.patientName,
                        medicamentName: medicament.name,
                        expirationDate: medicament.expirationDate,
                        previousStatus: previousStatus,
                        currentStatus: currentStatus
                    });
                }
            }

            // 4. Sauvegarder les nouveaux états
            const batch = db.batch();

            // Supprimer les anciens états
            previousStatesSnapshot.docs.forEach(doc => {
                batch.delete(doc.ref);
            });

            // Ajouter les nouveaux états
            currentStates.forEach((state, medicamentId) => {
                const stateRef = db.collection('medication_states').doc(medicamentId);
                batch.set(stateRef, state.toFirestore());
            });

            await batch.commit();

            // 5. Vérifier s'il faut envoyer une notification
            const hasNewAlerts = summary.newCriticalCount > 0 ||
                summary.newWarningCount > 0 ||
                summary.newExpiredCount > 0;

            if (hasNewAlerts) {
                // Sauvegarder le résumé quotidien
                await db.collection('daily_notifications').doc(today).set(summary.toFirestore());

                // Envoyer la notification push
                await sendGroupedNotification(summary);

                console.log(`Notification sent for ${today}: ${summary.newCriticalCount} critical, ${summary.newWarningCount} warning, ${summary.newExpiredCount} expired`);
            } else {
                console.log(`No new alerts for ${today}`);
            }

            console.log(`Check completed for ${today}: ${summary.totalCriticalCount} total critical, ${summary.totalWarningCount} total warning, ${summary.totalExpiredCount} total expired`);
            return null;

        } catch (error) {
            console.error('Error in checkMedicationExpirations:', error);
            throw error;
        }
    });

// Fonction pour envoyer la notification groupée
async function sendGroupedNotification(summary) {
    try {
        const notificationContent = createNotificationMessage(summary);

        const message = {
            notification: {
                title: notificationContent.title,
                body: notificationContent.body
            },
            data: {
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                screen: 'notifications',
                type: 'daily_medication_alert',
                date: summary.date,
                newCritical: summary.newCriticalCount.toString(),
                newWarning: summary.newWarningCount.toString(),
                newExpired: summary.newExpiredCount.toString()
            },
            topic: 'all_users'
        };

        const response = await admin.messaging().send(message);

        // Marquer comme envoyée
        await admin.firestore()
            .collection('daily_notifications')
            .doc(summary.date)
            .update({
                notificationSent: true,
                sentAt: admin.firestore.Timestamp.now()
            });

        console.log('Grouped notification sent successfully:', response);
        return response;

    } catch (error) {
        console.error('Error sending grouped notification:', error);
        throw error;
    }
}

// Fonction de retry pour les notifications échouées
exports.retryFailedNotifications = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 */2 * * *') // Toutes les 2 heures
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();
        const twoHoursAgo = new Date(now.toDate().getTime() - 2 * 60 * 60 * 1000);

        try {
            // Récupérer les notifications non envoyées ou en échec
            const failedNotifications = await db.collection('daily_notifications')
                .where('notificationSent', '==', false)
                .where('retryCount', '<', 3)
                .where('createdAt', '>', admin.firestore.Timestamp.fromDate(twoHoursAgo))
                .get();

            for (const doc of failedNotifications.docs) {
                const data = doc.data();
                const summary = Object.assign(new DailyNotificationSummary(), data);

                try {
                    await sendGroupedNotification(summary);
                    console.log(`Retry successful for notification ${doc.id}`);
                } catch (error) {
                    // Incrémenter le compteur de retry
                    await doc.ref.update({
                        retryCount: admin.firestore.FieldValue.increment(1),
                        lastRetryAt: now
                    });
                    console.error(`Retry failed for notification ${doc.id}:`, error);
                }
            }

            return null;
        } catch (error) {
            console.error('Error in retryFailedNotifications:', error);
            throw error;
        }
    });

// Fonction de nettoyage des anciennes données
exports.cleanupOldData = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 2 * * 0') // Tous les dimanches à 2h du matin
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();
        const oneMonthAgo = new Date();
        oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1);

        try {
            // Nettoyer les anciennes notifications quotidiennes
            const oldNotifications = await db.collection('daily_notifications')
                .where('createdAt', '<', admin.firestore.Timestamp.fromDate(oneMonthAgo))
                .get();

            const batch = db.batch();
            oldNotifications.docs.forEach(doc => {
                batch.delete(doc.ref);
            });

            // Nettoyer les anciennes notifications individuelles
            const oldIndividualNotifications = await db.collection('notifications')
                .where('createdAt', '<', admin.firestore.Timestamp.fromDate(oneMonthAgo))
                .get();

            oldIndividualNotifications.docs.forEach(doc => {
                batch.delete(doc.ref);
            });

            await batch.commit();

            console.log(`Cleanup completed: ${oldNotifications.size + oldIndividualNotifications.size} old records deleted`);
            return null;
        } catch (error) {
            console.error('Error in cleanup:', error);
            throw error;
        }
    });