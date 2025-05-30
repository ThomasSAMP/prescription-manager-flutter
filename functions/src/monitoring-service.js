const admin = require('firebase-admin');

class MonitoringService {
    constructor() {
        this.db = admin.firestore();
    }

    // Enregistrer une tentative de notification (simplifié)
    async logNotificationAttempt(type, status, details = {}) {
        try {
            const logEntry = {
                type: type, // 'push', 'sms', 'system'
                status: status, // 'success', 'failed', 'pending'
                timestamp: admin.firestore.Timestamp.now(),
                date: new Date().toISOString().split('T')[0],
                details: details
            };

            await this.db.collection('notification_logs').add(logEntry);
            console.log(`Logged ${type} notification attempt: ${status}`);
        } catch (error) {
            console.error('Error logging notification attempt:', error);
        }
    }

    // Enregistrer les statistiques quotidiennes (simplifié)
    async logDailyStats(date, stats) {
        try {
            await this.db.collection('daily_stats').doc(date).set({
                ...stats,
                timestamp: admin.firestore.Timestamp.now()
            }, { merge: true });
            console.log(`Daily stats logged for ${date}`);
        } catch (error) {
            console.error('Error logging daily stats:', error);
        }
    }

    // Obtenir les statistiques récentes
    async getRecentStats(days = 30) {
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - days);
            const cutoffDateStr = cutoffDate.toISOString().split('T')[0];

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

    // Obtenir les logs d'erreur récents
    async getRecentErrorLogs(days = 7) {
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - days);

            const snapshot = await this.db.collection('notification_logs')
                .where('status', '==', 'failed')
                .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(cutoffDate))
                .orderBy('timestamp', 'desc')
                .limit(50)
                .get();

            return snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data()
            }));
        } catch (error) {
            console.error('Error getting recent error logs:', error);
            return [];
        }
    }

    // Nettoyer les anciens logs (plus de 3 mois)
    async cleanupOldLogs() {
        try {
            const threeMonthsAgo = new Date();
            threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

            const oldLogsQuery = await this.db.collection('notification_logs')
                .where('timestamp', '<', admin.firestore.Timestamp.fromDate(threeMonthsAgo))
                .get();

            const batch = this.db.batch();
            oldLogsQuery.docs.forEach(doc => {
                batch.delete(doc.ref);
            });

            await batch.commit();
            console.log(`Cleaned up ${oldLogsQuery.size} old notification logs`);
        } catch (error) {
            console.error('Error cleaning up old logs:', error);
        }
    }
}

module.exports = { MonitoringService };