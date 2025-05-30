const admin = require('firebase-admin');

class MedicationAlert {
    constructor(medicamentId, ordonnanceId, patientName, medicamentName, expirationDate, alertLevel, alertDate) {
        this.medicamentId = medicamentId;
        this.ordonnanceId = ordonnanceId;
        this.patientName = patientName;
        this.medicamentName = medicamentName;
        this.expirationDate = expirationDate;
        this.alertLevel = alertLevel; // 'warning', 'critical', 'expired'
        this.alertDate = alertDate; // Format YYYY-MM-DD
        this.userStates = {}; // Sera rempli par utilisateur
        this.createdAt = admin.firestore.Timestamp.now();
    }

    toFirestore() {
        return {
            medicamentId: this.medicamentId,
            ordonnanceId: this.ordonnanceId,
            patientName: this.patientName,
            medicamentName: this.medicamentName,
            expirationDate: this.expirationDate,
            alertLevel: this.alertLevel,
            alertDate: this.alertDate,
            userStates: this.userStates,
            createdAt: this.createdAt
        };
    }

    static fromFirestore(data) {
        const alert = new MedicationAlert(
            data.medicamentId,
            data.ordonnanceId,
            data.patientName,
            data.medicamentName,
            data.expirationDate,
            data.alertLevel,
            data.alertDate
        );
        alert.userStates = data.userStates || {};
        alert.createdAt = data.createdAt;
        return alert;
    }
}

class MedicationTracking {
    constructor(medicamentId, currentStatus, checkDate) {
        this.medicamentId = medicamentId;
        this.lastStatus = currentStatus;
        this.lastCheckDate = checkDate;
        this.statusHistory = [];
        this.lastNotificationSent = null;
        this.updatedAt = admin.firestore.Timestamp.now();
    }

    addStatusChange(date, status) {
        this.statusHistory.unshift({ date, status, timestamp: admin.firestore.Timestamp.now() });
        // Garder seulement les 30 derniers changements
        if (this.statusHistory.length > 30) {
            this.statusHistory = this.statusHistory.slice(0, 30);
        }
    }

    toFirestore() {
        return {
            medicamentId: this.medicamentId,
            lastStatus: this.lastStatus,
            lastCheckDate: this.lastCheckDate,
            statusHistory: this.statusHistory,
            lastNotificationSent: this.lastNotificationSent,
            updatedAt: this.updatedAt
        };
    }

    static fromFirestore(data) {
        const tracking = new MedicationTracking(
            data.medicamentId,
            data.lastStatus,
            data.lastCheckDate
        );
        tracking.statusHistory = data.statusHistory || [];
        tracking.lastNotificationSent = data.lastNotificationSent;
        tracking.updatedAt = data.updatedAt;
        return tracking;
    }
}

class NotificationSummary {
    constructor(date) {
        this.date = date;
        this.newWarningCount = 0;
        this.newCriticalCount = 0;
        this.newExpiredCount = 0;
        this.newAlerts = [];
        this.createdAt = admin.firestore.Timestamp.now();
    }

    addAlert(alert) {
        this.newAlerts.push({
            medicamentId: alert.medicamentId,
            ordonnanceId: alert.ordonnanceId,
            patientName: alert.patientName,
            medicamentName: alert.medicamentName,
            alertLevel: alert.alertLevel
        });

        switch (alert.alertLevel) {
            case 'warning':
                this.newWarningCount++;
                break;
            case 'critical':
                this.newCriticalCount++;
                break;
            case 'expired':
                this.newExpiredCount++;
                break;
        }
    }

    hasNewAlerts() {
        return this.newWarningCount > 0 || this.newCriticalCount > 0 || this.newExpiredCount > 0;
    }

    toFirestore() {
        return {
            date: this.date,
            newWarningCount: this.newWarningCount,
            newCriticalCount: this.newCriticalCount,
            newExpiredCount: this.newExpiredCount,
            newAlerts: this.newAlerts,
            createdAt: this.createdAt
        };
    }
}

module.exports = { MedicationAlert, MedicationTracking, NotificationSummary };