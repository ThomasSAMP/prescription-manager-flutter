const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { MedicationAlert, MedicationTracking, NotificationSummary } = require('./src/models');
const { SMSService } = require('./src/sms-service');
const { MonitoringService } = require('./src/monitoring-service');

admin.initializeApp();

// Initialiser les services
const smsService = new SMSService();
const monitoringService = new MonitoringService();

// Fonction utilitaire pour déterminer le statut d'un médicament
function getMedicationStatus(expirationDate) {
    const now = new Date();
    let expDate;

    try {
        if (expirationDate && typeof expirationDate.toDate === 'function') {
            expDate = expirationDate.toDate();
        } else if (expirationDate instanceof Date) {
            expDate = expirationDate;
        } else if (typeof expirationDate === 'string') {
            expDate = new Date(expirationDate);
        } else if (expirationDate && typeof expirationDate === 'object' && expirationDate._seconds) {
            expDate = new Date(expirationDate._seconds * 1000);
        } else {
            console.error('Unsupported expiration date format:', expirationDate);
            return 'unknown';
        }

        if (isNaN(expDate.getTime())) {
            console.error('Invalid date created from:', expirationDate);
            return 'unknown';
        }

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

    } catch (error) {
        console.error('Error in getMedicationStatus:', error);
        return 'unknown';
    }
}

// Fonction principale de vérification des expirations
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
            // 1. Récupérer tous les médicaments
            const medicamentsSnapshot = await db.collection('medicaments').get();

            if (medicamentsSnapshot.empty) {
                console.log('No medications found');
                return null;
            }

            // 2. Récupérer les tracking existants
            const trackingSnapshot = await db.collection('medication_tracking').get();
            const existingTracking = new Map();

            trackingSnapshot.docs.forEach(doc => {
                const tracking = MedicationTracking.fromFirestore(doc.data());
                existingTracking.set(tracking.medicamentId, tracking);
            });

            // 3. Analyser les changements et créer les alertes
            const summary = new NotificationSummary(today);
            const batch = db.batch();
            const alertsToCreate = [];

            for (const doc of medicamentsSnapshot.docs) {
                const medicament = doc.data();
                medicament.id = doc.id;

                // Récupérer les informations de l'ordonnance
                const ordonnanceDoc = await db.collection('ordonnances').doc(medicament.ordonnanceId).get();
                if (!ordonnanceDoc.exists) continue;

                const ordonnance = ordonnanceDoc.data();
                const currentStatus = getMedicationStatus(medicament.expirationDate);

                // Ignorer les médicaments OK ou avec statut inconnu
                if (currentStatus === 'ok' || currentStatus === 'unknown') {
                    continue;
                }

                const existingTrack = existingTracking.get(medicament.id);
                const previousStatus = existingTrack ? existingTrack.lastStatus : 'ok';

                // Vérifier si c'est un NOUVEAU changement de statut
                const statusPriority = { 'ok': 0, 'warning': 1, 'critical': 2, 'expired': 3 };
                const isNewAlert = statusPriority[currentStatus] > statusPriority[previousStatus];

                if (isNewAlert) {
                    // Créer une nouvelle alerte
                    const alert = new MedicationAlert(
                        medicament.id,
                        medicament.ordonnanceId,
                        ordonnance.patientName,
                        medicament.name,
                        medicament.expirationDate,
                        currentStatus,
                        today
                    );

                    alertsToCreate.push(alert);
                    summary.addAlert(alert);

                    console.log(`New alert: ${medicament.name} changed from ${previousStatus} to ${currentStatus}`);
                }

                // Mettre à jour ou créer le tracking
                let tracking;
                if (existingTrack) {
                    tracking = existingTrack;
                    tracking.lastStatus = currentStatus;
                    tracking.lastCheckDate = today;
                    tracking.updatedAt = admin.firestore.Timestamp.now();

                    if (isNewAlert) {
                        tracking.addStatusChange(today, currentStatus);
                        tracking.lastNotificationSent = admin.firestore.Timestamp.now();
                    }
                } else {
                    tracking = new MedicationTracking(medicament.id, currentStatus, today);
                    if (isNewAlert) {
                        tracking.addStatusChange(today, currentStatus);
                        tracking.lastNotificationSent = admin.firestore.Timestamp.now();
                    }
                }

                // Ajouter au batch
                const trackingRef = db.collection('medication_tracking').doc(medicament.id);
                batch.set(trackingRef, tracking.toFirestore());
            }

            // 4. Sauvegarder les alertes
            for (const alert of alertsToCreate) {
                const alertRef = db.collection('medication_alerts').doc();
                batch.set(alertRef, alert.toFirestore());
            }

            // 5. Exécuter le batch
            await batch.commit();

            // 6. Envoyer les notifications si nécessaire
            if (summary.hasNewAlerts()) {
                await sendGroupedNotification(summary);
                console.log(`Notifications sent for ${today}: ${summary.newCriticalCount} critical, ${summary.newWarningCount} warning, ${summary.newExpiredCount} expired`);
            } else {
                console.log(`No new alerts for ${today}`);
            }

            // 7. Log des statistiques
            await monitoringService.logDailyStats(today, {
                totalMedications: medicamentsSnapshot.size,
                newCritical: summary.newCriticalCount,
                newWarning: summary.newWarningCount,
                newExpired: summary.newExpiredCount,
                notificationSent: summary.hasNewAlerts()
            });

            console.log(`Check completed for ${today}`);
            return null;

        } catch (error) {
            console.error('Error in checkMedicationExpirations:', error);
            await monitoringService.logNotificationAttempt('system', 'failed', {
                function: 'checkMedicationExpirations',
                error: error.message
            });
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
            // Configuration Android spécifique pour les heads-up notifications
            android: {
                notification: {
                    channelId: 'medication_alerts',
                    priority: 'high',
                    defaultSound: true,
                    defaultVibrateTimings: true,
                    defaultLightSettings: true,
                    notificationPriority: 'PRIORITY_HIGH',
                    visibility: 'PUBLIC'
                }
            },
            // Configuration iOS spécifique
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                        alert: {
                            title: notificationContent.title,
                            body: notificationContent.body
                        }
                    }
                }
            },
            topic: 'all_users'
        };

        await monitoringService.logNotificationAttempt('push', 'pending', {
            date: summary.date,
            recipientCount: 'all_users',
            messageLength: notificationContent.body.length
        });

        const response = await admin.messaging().send(message);

        await monitoringService.logNotificationAttempt('push', 'success', {
            date: summary.date,
            messageId: response,
            recipientCount: 'all_users'
        });

        console.log('Grouped notification sent successfully:', response);
        return response;

    } catch (error) {
        await monitoringService.logNotificationAttempt('push', 'failed', {
            date: summary.date,
            error: error.message,
            recipientCount: 'all_users'
        });

        console.error('Error sending grouped notification:', error);
        throw error;
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
        body: lines.slice(1).join('\n')
    };
}

// Fonction de nettoyage automatique (6 mois)
exports.cleanupOldAlerts = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 2 * * 0') // Tous les dimanches à 2h
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();
        const sixMonthsAgo = new Date();
        sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
        const cutoffDate = sixMonthsAgo.toISOString().split('T')[0];

        try {
            // Nettoyer les anciennes alertes
            const oldAlertsQuery = await db.collection('medication_alerts')
                .where('alertDate', '<', cutoffDate)
                .get();

            const batch = db.batch();
            oldAlertsQuery.docs.forEach(doc => {
                batch.delete(doc.ref);
            });

            // Nettoyer les tracking des médicaments supprimés
            const trackingSnapshot = await db.collection('medication_tracking').get();
            const medicamentsSnapshot = await db.collection('medicaments').get();
            const existingMedicamentIds = new Set(medicamentsSnapshot.docs.map(doc => doc.id));

            trackingSnapshot.docs.forEach(doc => {
                if (!existingMedicamentIds.has(doc.data().medicamentId)) {
                    batch.delete(doc.ref);
                }
            });

            await batch.commit();

            console.log(`Cleanup completed: ${oldAlertsQuery.size} old alerts deleted`);
            return null;
        } catch (error) {
            console.error('Error in cleanup:', error);
            throw error;
        }
    });

// Garder les fonctions de retry et monitoring existantes mais simplifiées
exports.retryFailedNotifications = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 */2 * * *')
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        // Logique de retry simplifiée
        console.log('Retry function - to be implemented if needed');
        return null;
    });

// Fonction de test SMS (inchangée)
exports.testSMSService = functions
    .region('europe-west1')
    .https
    .onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
        }

        const phoneNumber = data.phoneNumber;
        if (!phoneNumber) {
            throw new functions.https.HttpsError('invalid-argument', 'Phone number is required');
        }

        try {
            const result = await smsService.testSMS(phoneNumber);
            return {
                success: result.success,
                messageId: result.messageId,
                status: result.status,
                error: result.error,
                serviceStatus: smsService.getServiceStatus()
            };
        } catch (error) {
            console.error('Error testing SMS service:', error);
            throw new functions.https.HttpsError('internal', 'Error testing SMS service');
        }
    });

// Fonction pour obtenir les statistiques
exports.getNotificationStats = functions
    .region('europe-west1')
    .https
    .onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
        }

        try {
            const days = data.days || 30;
            const stats = await monitoringService.getRecentStats(days);

            return {
                stats: stats,
                generatedAt: admin.firestore.Timestamp.now()
            };
        } catch (error) {
            console.error('Error getting notification stats:', error);
            throw new functions.https.HttpsError('internal', 'Error retrieving stats');
        }
    });

// Fonction de nettoyage automatique étendue
exports.cleanupOldData = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 2 * * 0') // Tous les dimanches à 2h
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();
        const sixMonthsAgo = new Date();
        sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
        const cutoffDate = sixMonthsAgo.toISOString().split('T')[0];

        try {
            const batch = db.batch();
            let totalDeleted = 0;

            // 1. Nettoyer les anciennes alertes (6 mois)
            const oldAlertsQuery = await db.collection('medication_alerts')
                .where('alertDate', '<', cutoffDate)
                .get();

            oldAlertsQuery.docs.forEach(doc => {
                batch.delete(doc.ref);
                totalDeleted++;
            });

            // 2. Nettoyer les tracking des médicaments supprimés
            const trackingSnapshot = await db.collection('medication_tracking').get();
            const medicamentsSnapshot = await db.collection('medicaments').get();
            const existingMedicamentIds = new Set(medicamentsSnapshot.docs.map(doc => doc.id));

            trackingSnapshot.docs.forEach(doc => {
                if (!existingMedicamentIds.has(doc.data().medicamentId)) {
                    batch.delete(doc.ref);
                    totalDeleted++;
                }
            });

            // 3. Nettoyer les anciennes stats (1 an)
            const oneYearAgo = new Date();
            oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);
            const oneYearCutoff = oneYearAgo.toISOString().split('T')[0];

            const oldStatsQuery = await db.collection('daily_stats')
                .where('timestamp', '<', admin.firestore.Timestamp.fromDate(oneYearAgo))
                .get();

            oldStatsQuery.docs.forEach(doc => {
                batch.delete(doc.ref);
                totalDeleted++;
            });

            await batch.commit();

            // 4. Nettoyer les anciens logs via le service de monitoring
            await monitoringService.cleanupOldLogs();

            console.log(`Cleanup completed: ${totalDeleted} records deleted`);

            // Log de l'opération de nettoyage
            await monitoringService.logDailyStats(new Date().toISOString().split('T')[0], {
                cleanupPerformed: true,
                recordsDeleted: totalDeleted
            });

            return null;
        } catch (error) {
            console.error('Error in cleanup:', error);
            await monitoringService.logNotificationAttempt('system', 'failed', {
                function: 'cleanupOldData',
                error: error.message
            });
            throw error;
        }
    });

// Fonction pour nettoyer les collections de notifications (DEV ONLY)
exports.clearNotificationCollections = functions
    .region('europe-west1')
    .https
    .onCall(async (data, context) => {
        // Vérifier l'authentification
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
        }

        // SÉCURITÉ: Cette fonction ne devrait être utilisée qu'en développement
        // Vous pouvez ajouter une vérification supplémentaire ici si nécessaire
        // Par exemple, vérifier si l'utilisateur est admin ou si on est en mode dev

        const db = admin.firestore();

        try {
            console.log('Starting to clear notification collections...');

            // Collections à nettoyer
            const collectionsToDelete = [
                'daily_stats',
                'medication_alerts',
                'medication_tracking',
                'notification_logs'
            ];

            let totalDeleted = 0;
            const results = {};

            // Nettoyer chaque collection
            for (const collectionName of collectionsToDelete) {
                console.log(`Clearing collection: ${collectionName}`);

                const collectionRef = db.collection(collectionName);
                const snapshot = await collectionRef.get();

                console.log(`Found ${snapshot.size} documents in ${collectionName}`);

                if (snapshot.size > 0) {
                    // Utiliser un batch pour supprimer par groupes de 500 (limite Firestore)
                    const batches = [];
                    let batch = db.batch();
                    let batchCount = 0;

                    snapshot.docs.forEach((doc) => {
                        batch.delete(doc.ref);
                        batchCount++;

                        // Firestore limite les batches à 500 opérations
                        if (batchCount === 500) {
                            batches.push(batch);
                            batch = db.batch();
                            batchCount = 0;
                        }
                    });

                    // Ajouter le dernier batch s'il contient des opérations
                    if (batchCount > 0) {
                        batches.push(batch);
                    }

                    // Exécuter tous les batches
                    await Promise.all(batches.map(b => b.commit()));

                    results[collectionName] = snapshot.size;
                    totalDeleted += snapshot.size;
                } else {
                    results[collectionName] = 0;
                }
            }

            console.log(`Successfully cleared ${totalDeleted} documents across all collections`);

            return {
                success: true,
                totalDeleted: totalDeleted,
                collections: results,
                message: `Successfully cleared ${totalDeleted} documents`
            };

        } catch (error) {
            console.error('Error clearing notification collections:', error);
            throw new functions.https.HttpsError('internal', 'Error clearing collections: ' + error.message);
        }
    });