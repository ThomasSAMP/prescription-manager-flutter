const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { MedicationState, DailyNotificationSummary } = require('./src/models');
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
        // Log pour débugger le type de données reçu
        console.log('Processing expiration date:', {
            value: expirationDate,
            type: typeof expirationDate,
            constructor: expirationDate?.constructor?.name,
            hasToDate: typeof expirationDate?.toDate === 'function'
        });

        // Gérer différents types de dates
        if (expirationDate && typeof expirationDate.toDate === 'function') {
            // C'est un Timestamp Firestore
            expDate = expirationDate.toDate();
            console.log('Converted Firestore Timestamp to Date:', expDate);
        } else if (expirationDate instanceof Date) {
            // C'est déjà un objet Date
            expDate = expirationDate;
            console.log('Already a Date object:', expDate);
        } else if (typeof expirationDate === 'string') {
            // C'est une chaîne de caractères
            expDate = new Date(expirationDate);
            console.log('Converted string to Date:', expDate);
        } else if (expirationDate && typeof expirationDate === 'object' && expirationDate._seconds) {
            // C'est un Timestamp Firestore sérialisé
            expDate = new Date(expirationDate._seconds * 1000);
            console.log('Converted serialized Timestamp to Date:', expDate);
        } else {
            console.error('Unsupported expiration date format:', {
                value: expirationDate,
                type: typeof expirationDate
            });
            return 'unknown';
        }

        // Vérifier que la date est valide
        if (isNaN(expDate.getTime())) {
            console.error('Invalid date created from:', expirationDate);
            return 'unknown';
        }

        const diffInDays = Math.ceil((expDate - now) / (1000 * 60 * 60 * 24));
        console.log(`Date comparison: expDate=${expDate.toISOString()}, now=${now.toISOString()}, diffInDays=${diffInDays}`);

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
        console.error('ExpirationDate value:', expirationDate);
        return 'unknown';
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

async function createIndividualNotifications(summary, db) {
    if (summary.newMedications.length === 0) return;

    const batch = db.batch();
    const notificationsRef = db.collection('notifications');
    const now = admin.firestore.Timestamp.now();

    for (const med of summary.newMedications) {
        let title, body, type;

        switch (med.currentStatus) {
            case 'expired':
                title = 'Médicament expiré !';
                body = `Le médicament ${med.medicamentName} a expiré.`;
                type = 'expiration_critical';
                break;
            case 'critical':
                title = 'Médicament bientôt expiré !';
                body = `Le médicament ${med.medicamentName} expire dans moins de 14 jours.`;
                type = 'expiration_critical';
                break;
            case 'warning':
                title = 'Attention à l\'expiration';
                body = `Le médicament ${med.medicamentName} expire dans moins de 30 jours.`;
                type = 'expiration_warning';
                break;
            default:
                continue;
        }

        const notifRef = notificationsRef.doc();
        batch.set(notifRef, {
            title: title,
            body: body,
            type: type,
            medicamentId: med.medicamentId,
            ordonnanceId: med.ordonnanceId,
            patientName: med.patientName,
            medicamentName: med.medicamentName,
            expirationDate: med.expirationDate,
            createdAt: now
        });
    }

    await batch.commit();
    console.log(`Created ${summary.newMedications.length} individual notifications`);
}

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
            const summary = new DailyNotificationSummary(today, admin.firestore.Timestamp.now());

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
                    currentStatus,
                    admin.firestore.Timestamp.now()
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

                // Créer les notifications individuelles pour NotificationsScreen
                await createIndividualNotifications(summary, db);

                // Envoyer la notification push
                await sendGroupedNotification(summary);

                console.log(`Notification sent for ${today}: ${summary.newCriticalCount} critical, ${summary.newWarningCount} warning, ${summary.newExpiredCount} expired`);
            } else {
                console.log(`No new alerts for ${today}`);
            }

            console.log(`Check completed for ${today}: ${summary.totalCriticalCount} total critical, ${summary.totalWarningCount} total warning, ${summary.totalExpiredCount} total expired`);

            await monitoringService.logDailyStats(today, {
                totalMedications: medicamentsSnapshot.size,
                newCritical: summary.newCriticalCount,
                newWarning: summary.newWarningCount,
                newExpired: summary.newExpiredCount,
                totalCritical: summary.totalCriticalCount,
                totalWarning: summary.totalWarningCount,
                totalExpired: summary.totalExpiredCount,
                notificationSent: hasNewAlerts
            });

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
            topic: 'all_users'
        };

        // Enregistrer la tentative
        await monitoringService.logNotificationAttempt('push', 'pending', {
            date: summary.date,
            recipientCount: 'all_users',
            messageLength: notificationContent.body.length
        });

        const response = await admin.messaging().send(message);

        // Marquer comme envoyée
        await admin.firestore()
            .collection('daily_notifications')
            .doc(summary.date)
            .update({
                notificationSent: true,
                sentAt: admin.firestore.Timestamp.now()
            });

        // Enregistrer le succès
        await monitoringService.logNotificationAttempt('push', 'success', {
            date: summary.date,
            messageId: response,
            recipientCount: 'all_users'
        });

        console.log('Grouped notification sent successfully:', response);
        return response;

    } catch (error) {
        // Enregistrer l'échec
        await monitoringService.logNotificationAttempt('push', 'failed', {
            date: summary.date,
            error: error.message,
            recipientCount: 'all_users'
        });

        console.error('Error sending grouped notification:', error);
        throw error;
    }
}

// Fonction pour récupérer les numéros de téléphone des utilisateurs
async function getUserPhoneNumbers() {
    try {
        const db = admin.firestore();

        // Récupérer tous les utilisateurs qui ont un numéro de téléphone
        const usersSnapshot = await db.collection('users')
            .where('phoneNumber', '!=', null)
            .get();

        const phoneNumbers = [];
        usersSnapshot.docs.forEach(doc => {
            const userData = doc.data();
            // Vérifier que le numéro existe ET que les SMS ne sont pas explicitement désactivés
            if (userData.phoneNumber && userData.smsNotificationsEnabled !== false) {
                phoneNumbers.push(userData.phoneNumber);
            }
        });

        console.log(`Found ${phoneNumbers.length} users with phone numbers for SMS`);
        return phoneNumbers;
    } catch (error) {
        console.error('Error getting user phone numbers:', error);
        return [];
    }
}

// Fonction de fallback SMS
async function attemptSMSFallback(summary) {
    try {
        console.log(`Attempting SMS fallback for ${summary.date}`);

        await monitoringService.logNotificationAttempt('sms', 'pending', {
            date: summary.date,
            reason: 'push_notification_failed_after_retries'
        });

        // Récupérer les numéros de téléphone des utilisateurs
        const phoneNumbers = await getUserPhoneNumbers();

        if (phoneNumbers.length === 0) {
            console.log('No phone numbers found for SMS fallback');
            await monitoringService.logNotificationAttempt('sms', 'failed', {
                date: summary.date,
                error: 'No phone numbers available'
            });
            return;
        }

        // Créer le message SMS
        const smsMessage = smsService.createMedicationAlertSMS(summary);

        // Envoyer les SMS
        const smsResult = await smsService.sendBulkSMS(phoneNumbers, smsMessage);

        if (smsResult.success) {
            await monitoringService.logNotificationAttempt('sms', 'success', {
                date: summary.date,
                recipientCount: smsResult.totalSent,
                totalCost: 'calculated_by_twilio'
            });
            console.log(`SMS fallback successful for ${summary.date}: ${smsResult.totalSent} sent`);
        } else {
            await monitoringService.logNotificationAttempt('sms', 'partial_success', {
                date: summary.date,
                successCount: smsResult.totalSent,
                failureCount: smsResult.totalFailed,
                details: smsResult.results
            });
            console.log(`SMS fallback partially successful for ${summary.date}: ${smsResult.totalSent}/${phoneNumbers.length} sent`);
        }

    } catch (error) {
        console.error('Error in SMS fallback:', error);
        await monitoringService.logNotificationAttempt('sms', 'failed', {
            date: summary.date,
            error: error.message
        });
    }
}

// Fonction de retry pour les notifications échouées
exports.retryFailedNotifications = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 */2 * * *')
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        const db = admin.firestore();
        const now = admin.firestore.Timestamp.now();
        const twelveHoursAgo = new Date(now.toDate().getTime() - 12 * 60 * 60 * 1000);

        try {
            const failedNotifications = await db.collection('daily_notifications')
                .where('notificationSent', '==', false)
                .where('retryCount', '<', 3)
                .where('createdAt', '>', admin.firestore.Timestamp.fromDate(twelveHoursAgo))
                .get();

            for (const doc of failedNotifications.docs) {
                const data = doc.data();

                const summary = new DailyNotificationSummary(data.date, data.createdAt);
                summary.newCriticalCount = data.newCriticalCount || 0;
                summary.newWarningCount = data.newWarningCount || 0;
                summary.newExpiredCount = data.newExpiredCount || 0;
                summary.totalCriticalCount = data.totalCriticalCount || 0;
                summary.totalWarningCount = data.totalWarningCount || 0;
                summary.totalExpiredCount = data.totalExpiredCount || 0;
                summary.newMedications = data.newMedications || [];
                summary.notificationSent = data.notificationSent || false;
                summary.sentAt = data.sentAt;
                summary.retryCount = data.retryCount || 0;
                summary.lastRetryAt = data.lastRetryAt;

                try {
                    await sendGroupedNotification(summary);
                    console.log(`Retry successful for notification ${doc.id}`);
                } catch (error) {
                    const newRetryCount = (data.retryCount || 0) + 1;

                    await doc.ref.update({
                        retryCount: newRetryCount,
                        lastRetryAt: now
                    });

                    console.error(`Retry ${newRetryCount} failed for notification ${doc.id}:`, error);

                    if (newRetryCount >= 3) {
                        await attemptSMSFallback(summary);
                    }
                }
            }

            return null;
        } catch (error) {
            console.error('Error in retryFailedNotifications:', error);
            await monitoringService.logNotificationAttempt('retry', 'failed', {
                error: error.message
            });
            throw error;
        }
    });

exports.testSMSService = functions
    .region('europe-west1')
    .https
    .onCall(async (data, context) => {
        // Vérifier l'authentification
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

// Fonction de monitoring quotidien
exports.dailyHealthCheck = functions
    .region('europe-west1')
    .pubsub
    .schedule('0 20 * * *') // Tous les jours à 20h
    .timeZone('Europe/Paris')
    .onRun(async (context) => {
        try {
            const health = await monitoringService.checkSystemHealth();

            // Enregistrer les statistiques de santé
            const today = new Date().toISOString().split('T')[0];
            await monitoringService.logDailyStats(today, {
                systemHealth: health,
                checksPerformed: 1
            });

            // Si le système n'est pas en bonne santé, logger une alerte
            if (health.status !== 'healthy') {
                console.warn(`System health check failed for ${today}:`, health);

                // Ici, nous pourrions envoyer une alerte aux administrateurs
                // Par exemple, un email ou une notification spéciale
            }

            console.log(`Daily health check completed for ${today}:`, health.status);
            return null;
        } catch (error) {
            console.error('Error in daily health check:', error);
            throw error;
        }
    });

// Fonction pour obtenir les statistiques (pour un dashboard admin)
exports.getNotificationStats = functions
    .region('europe-west1')
    .https
    .onCall(async (data, context) => {
        // Vérifier l'authentification (à implémenter selon vos besoins)
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
        }

        try {
            const days = data.days || 30;
            const stats = await monitoringService.getRecentStats(days);
            const health = await monitoringService.checkSystemHealth();

            return {
                stats: stats,
                currentHealth: health,
                generatedAt: admin.firestore.Timestamp.now()
            };
        } catch (error) {
            console.error('Error getting notification stats:', error);
            throw new functions.https.HttpsError('internal', 'Error retrieving stats');
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