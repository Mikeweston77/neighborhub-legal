# Email Configuration Guide for NeighborHub

## Overview
NeighborHub now sends email notifications when users are approved or rejected by administrators. This guide explains how to configure the email service properly.

## Current Implementation
- ✅ **Email Service**: Nodemailer with Gmail SMTP
- ✅ **Templates**: HTML email templates for approval and rejection
- ✅ **Integration**: Automatic email sending in `onUserApproval` Cloud Function
- ✅ **Cross-Platform**: Works for both iOS and Android users

## Email Configuration Steps

### Step 1: Set Up Gmail App Password (Recommended)
1. Enable 2-Factor Authentication on your Gmail account
2. Go to Google Account settings → Security → 2-Step Verification
3. Generate an "App Password" for NeighborHub
4. Use this app password (not your regular Gmail password)

### Step 2: Configure Firebase Functions Environment
Replace the example configuration with your actual email credentials:

```bash
# Navigate to your project directory
cd "/Users/mike/Desktop/Waterfall 3 V1.05"

# Set your actual email configuration
firebase functions:config:set gmail.email="your-actual-email@gmail.com" gmail.password="your-app-password"

# Redeploy the function to apply changes
firebase deploy --only functions:onUserApproval
```

### Step 3: Alternative Email Providers
You can modify `functions/index.js` to use other email services:

#### SendGrid (Recommended for production)
```javascript
const emailConfig = {
  service: 'SendGrid',
  auth: {
    user: 'apikey',
    pass: functions.config().sendgrid?.key || 'your-sendgrid-api-key'
  }
};
```

#### Custom SMTP
```javascript
const emailConfig = {
  host: 'your-smtp-server.com',
  port: 587,
  secure: false,
  auth: {
    user: functions.config().smtp?.user || 'your-username',
    pass: functions.config().smtp?.password || 'your-password'
  }
};
```

## Email Templates

### Approval Email Features
- ✅ Professional HTML design with NeighborHub branding
- ✅ Welcoming tone with community feature overview
- ✅ Mobile-responsive design
- ✅ Clear call-to-action

### Rejection Email Features
- ✅ Respectful and supportive tone
- ✅ Clear explanation of potential reasons
- ✅ Contact information for appeals
- ✅ Professional presentation

## Email Flow

### When User is Approved:
1. Admin calls `approveUser()` method (iOS/Android)
2. Firestore user document updated: `verified: true`
3. Cloud Function `onUserApproval` triggers automatically
4. **Push Notification** sent to user's device
5. **Email** sent to user's email address
6. User receives both notifications

### When User is Rejected:
1. Admin calls `rejectUser()` method or sets `rejected: true`
2. Firestore user document updated
3. Cloud Function triggers automatically
4. **Push Notification** sent to user's device
5. **Email** sent to user's email address
6. User receives both notifications

## Testing

### Test Approval Email:
```javascript
// In Firebase Console Functions logs, you'll see:
// "✅ User approved: John Doe (uid123)"
// "✅ Email sent successfully to john@example.com"
```

### Test Rejection Email:
```javascript
// In Firebase Console Functions logs, you'll see:
// "❌ User rejected: Jane Smith (uid456)"
// "✅ Email sent successfully to jane@example.com"
```

## Troubleshooting

### Common Issues:

1. **"Authentication failed" error**
   - Verify Gmail app password is correct
   - Ensure 2FA is enabled on Gmail account
   - Check email configuration in Firebase Functions

2. **"Email not sent" warning**
   - User document missing email field
   - Check Firestore user document structure
   - Verify email address format

3. **Function deployment fails**
   - Check nodemailer dependency installation
   - Verify Firebase Functions configuration
   - Review Cloud Function logs for specific errors

### Check Configuration:
```bash
firebase functions:config:get
```

### View Function Logs:
```bash
firebase functions:log --only onUserApproval
```

## Security Notes

- ✅ Email credentials stored securely in Firebase Functions config
- ✅ No email addresses exposed in client code
- ✅ Automated email sending prevents spam/abuse
- ✅ Professional email templates maintain brand reputation

## Production Recommendations

1. **Use SendGrid or similar service** for better deliverability
2. **Set up SPF/DKIM records** for your domain
3. **Monitor email delivery rates** in production
4. **Consider email rate limiting** for high-volume scenarios
5. **Add unsubscribe options** if required by regulations

## Current Status: ✅ FULLY IMPLEMENTED

Both iOS and Android users will now receive:
- **Push notifications** (immediate, on-device)
- **Email notifications** (persistent, in inbox)

When their account approval status changes.