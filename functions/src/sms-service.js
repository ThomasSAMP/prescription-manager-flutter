const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

class SMSService {
    constructor() {
        // Vérifier si Twilio est configuré
        try {
            const config = functions.config();
            this.isEnabled = !!(config.twilio && config.twilio.account_sid && config.twilio.auth_token);

            if (this.isEnabled) {
                this.accountSid = config.twilio.account_sid;
                this.authToken = config.twilio.auth_token;
                this.fromNumber = config.twilio.phone_number;
                this.client = require('twilio')(this.accountSid, this.authToken);
                console.log('Twilio SMS service initialized successfully');
            } else {
                console.log('Twilio SMS service not configured - SMS fallback disabled');
            }
        } catch (error) {
            console.error('Error initializing Twilio SMS service:', error);
            this.isEnabled = false;
        }
    }

    // Méthode pour envoyer un SMS
    async sendSMS(phoneNumber, message) {
        if (!this.isEnabled) {
            console.log(`SMS service disabled. Would send to ${phoneNumber}: ${message}`);
            return { success: false, reason: 'SMS service not configured' };
        }

        try {
            // Valider le format du numéro de téléphone
            if (!this.isValidPhoneNumber(phoneNumber)) {
                throw new Error(`Invalid phone number format: ${phoneNumber}`);
            }

            const result = await this.client.messages.create({
                body: message,
                from: this.fromNumber,
                to: phoneNumber
            });

            console.log(`SMS sent successfully to ${phoneNumber}, SID: ${result.sid}`);
            return {
                success: true,
                messageId: result.sid,
                status: result.status,
                cost: result.price || '0'
            };
        } catch (error) {
            console.error(`Error sending SMS to ${phoneNumber}:`, error);
            return {
                success: false,
                error: error.message,
                code: error.code || 'UNKNOWN_ERROR'
            };
        }
    }

    // Valider le format du numéro de téléphone
    isValidPhoneNumber(phoneNumber) {
        // Format international requis : +33123456789
        const phoneRegex = /^\+[1-9]\d{1,14}$/;
        return phoneRegex.test(phoneNumber);
    }

    // Envoyer des SMS à plusieurs destinataires
    async sendBulkSMS(phoneNumbers, message) {
        if (!this.isEnabled) {
            console.log(`SMS service disabled. Would send bulk SMS to ${phoneNumbers.length} recipients`);
            return { success: false, reason: 'SMS service not configured' };
        }

        const results = [];
        const maxConcurrent = 5; // Limiter les envois simultanés pour éviter les rate limits

        for (let i = 0; i < phoneNumbers.length; i += maxConcurrent) {
            const batch = phoneNumbers.slice(i, i + maxConcurrent);
            const batchPromises = batch.map(async (phoneNumber) => {
                const result = await this.sendSMS(phoneNumber, message);
                return { phoneNumber, ...result };
            });

            const batchResults = await Promise.allSettled(batchPromises);
            results.push(...batchResults.map(r => r.status === 'fulfilled' ? r.value : {
                phoneNumber: 'unknown',
                success: false,
                error: r.reason?.message || 'Promise rejected'
            }));

            // Pause entre les batches pour respecter les rate limits
            if (i + maxConcurrent < phoneNumbers.length) {
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
        }

        const successCount = results.filter(r => r.success).length;
        const failureCount = results.length - successCount;

        console.log(`Bulk SMS completed: ${successCount} success, ${failureCount} failures`);

        return {
            success: failureCount === 0,
            totalSent: successCount,
            totalFailed: failureCount,
            results: results
        };
    }

    // Créer le message SMS pour les alertes de médicaments
    createMedicationAlertSMS(summary) {
        const lines = ['🏥 Prescription Manager'];
        lines.push('Alertes médicaments:');

        if (summary.newExpiredCount > 0) {
            lines.push(`🚨 ${summary.newExpiredCount} médicament${summary.newExpiredCount > 1 ? 's' : ''} expiré${summary.newExpiredCount > 1 ? 's' : ''}`);
        }

        if (summary.newCriticalCount > 0) {
            lines.push(`⚠️ ${summary.newCriticalCount} médicament${summary.newCriticalCount > 1 ? 's' : ''} critique${summary.newCriticalCount > 1 ? 's' : ''}`);
        }

        if (summary.newWarningCount > 0) {
            lines.push(`🟡 ${summary.newWarningCount} médicament${summary.newWarningCount > 1 ? 's' : ''} en alerte`);
        }

        lines.push('');
        lines.push('Consultez l\'app pour plus de détails.');

        return lines.join('\n');
    }

    // Obtenir le statut du service SMS
    getServiceStatus() {
        return {
            enabled: this.isEnabled,
            provider: 'Twilio',
            fromNumber: this.fromNumber || 'Not configured'
        };
    }

    // Tester l'envoi SMS
    async testSMS(phoneNumber) {
        const testMessage = 'Test SMS depuis Prescription Manager. Ce message confirme que le service SMS fonctionne correctement.';
        return await this.sendSMS(phoneNumber, testMessage);
    }
}

module.exports = { SMSService };