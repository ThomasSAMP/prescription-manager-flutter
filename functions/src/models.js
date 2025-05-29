// Modèles pour la gestion des notifications
class MedicationState {
    constructor(medicamentId, ordonnanceId, patientName, medicamentName, expirationDate, status, lastChecked = null) {
        this.medicamentId = medicamentId;
        this.ordonnanceId = ordonnanceId;
        this.patientName = patientName;
        this.medicamentName = medicamentName;
        this.expirationDate = expirationDate;
        this.status = status; // 'ok', 'warning', 'critical', 'expired'
        this.lastChecked = lastChecked || admin.firestore.Timestamp.now();
    }

    toFirestore() {
        return {
            medicamentId: this.medicamentId,
            ordonnanceId: this.ordonnanceId,
            patientName: this.patientName,
            medicamentName: this.medicamentName,
            expirationDate: this.expirationDate,
            status: this.status,
            lastChecked: this.lastChecked
        };
    }

    static fromFirestore(data) {
        return new MedicationState(
            data.medicamentId,
            data.ordonnanceId,
            data.patientName,
            data.medicamentName,
            data.expirationDate,
            data.status,
            data.lastChecked
        );
    }
}

class DailyNotificationSummary {
    constructor(date) {
        this.date = date;
        this.newCriticalCount = 0;
        this.newWarningCount = 0;
        this.newExpiredCount = 0;
        this.totalCriticalCount = 0;
        this.totalWarningCount = 0;
        this.totalExpiredCount = 0;
        this.newMedications = [];
        this.notificationSent = false;
        this.sentAt = null;
        this.retryCount = 0;
        this.lastRetryAt = null;
        this.createdAt = admin.firestore.Timestamp.now();
    }

    toFirestore() {
        return {
            date: this.date,
            newCriticalCount: this.newCriticalCount,
            newWarningCount: this.newWarningCount,
            newExpiredCount: this.newExpiredCount,
            totalCriticalCount: this.totalCriticalCount,
            totalWarningCount: this.totalWarningCount,
            totalExpiredCount: this.totalExpiredCount,
            newMedications: this.newMedications,
            notificationSent: this.notificationSent,
            sentAt: this.sentAt,
            retryCount: this.retryCount,
            lastRetryAt: this.lastRetryAt,
            createdAt: this.createdAt
        };
    }
}

module.exports = { MedicationState, DailyNotificationSummary };