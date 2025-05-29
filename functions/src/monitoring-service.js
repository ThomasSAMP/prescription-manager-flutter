const admin = require('firebase-admin');

class MonitoringService {
    constructor() {
        this.db = admin.firestore();
    }

    // Enregistrer une tentative de notification
    async logNotificationAttempt(type, status, details = {}) {
        try {
            const logEntry = {
                type: type, // 'push', 'sms', 'retry'
                status: status, // 'success', 'failed', 'pending'
                timestamp: admin.firestore.Timestamp.now(),
                details: details
            };

            await this.db.collection('notification_logs').add(logEntry);
            console.log(`Logged ${type} notification attempt: ${status}`);
        } catch (error) {
            console.error('Error logging notification attempt:', error);
        }
    }

    // Enregistrer les statistiques quotidiennes
    async logDailyStats(date, stats) {
        try {
            await this.db.collection('daily_stats').doc(date).set({
                ...stats,
                timestamp: admin.firestore.Timestamp.now()
            });
            console.log(`Daily stats logged for ${date}`);
        } catch (error) {
            console.error('Error logging daily stats:', error);
        }
    }

    // Obtenir les statistiques des 30 derniers jours
    async getRecentStats(days = 30) {
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - days);

            const snapshot = await this.db.collection('daily_stats')
                .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(cutoffDate))
                .orderBy('timestamp', 'desc')
                .get();

            return snapshot.docs.map(doc => ({
                date: doc.id,
                ...doc.data()
            }));
        } catch (error) {
            console.error('Error getting recent stats:', error);
            return [];
        }
    }

    // Vérifier la santé du système de notifications
    async checkSystemHealth() {
        try {
            const today = new Date().toISOString().split('T')[0];
            const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0];

            // Vérifier les notifications d'aujourd'hui
            const todayNotification = await this.db.collection('daily_notifications').doc(today).get();

            // Vérifier les logs des dernières 24h
            const recentLogs = await this.db.collection('notification_logs')
                .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000)))
                .get();

            const health = {
                date: today,
                todayNotificationExists: todayNotification.exists,
                todayNotificationSent: todayNotification.exists ? todayNotification.data()?.notificationSent : false,
                recentLogsCount: recentLogs.size,
                lastLogTime: recentLogs.empty ? null : recentLogs.docs[0].data().timestamp,
                status: 'healthy'
            };

            // Déterminer le statut de santé
            if (!todayNotification.exists && new Date().getHours() > 9) {
                health.status = 'warning'; // Pas de notification après 9h
            }

            if (recentLogs.size === 0) {
                health.status = 'error'; // Aucun log récent
            }

            return health;
        } catch (error) {
            console.error('Error checking system health:', error);
            return { status: 'error', error: error.message };
        }
    }
}

module.exports = { MonitoringService };