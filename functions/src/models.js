// Modèles pour la gestion des notifications
class MedicationState {
    constructor(medicamentId, ordonnanceId, patientName, medicamentName, expirationDate, status, lastChecked = null) {
        this.medicamentId = medicamentId;
        this.ordonnanceId = ordonnanceId;
        this.patientName = patientName;
        this.medicamentName = medicamentName;
        this.expirationDate = expirationDate;
        this.status = status; // 'ok', 'warning', 'critical', 'expired'
        this.lastChecked = lastChecked;
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
    constructor(date, createdAt = null) {
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
        this.createdAt = createdAt;
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

    static fromFirestore(data) {
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
        return summary;
    }
}

module.exports = { MedicationState, DailyNotificationSummary };