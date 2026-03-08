# WhatsApp Server Example

This small Express server demonstrates how to accept help requests from your iOS app and send a WhatsApp message via the WhatsApp Cloud API (Meta).

Quick start:

1. Copy `.env.example` to `.env` and fill in your `WHATSAPP_PHONE_ID`, `WHATSAPP_TOKEN`, and `API_KEY`.

2. Install and run:

```bash
npm install
npm start
```

3. For local testing from a device/simulator, expose the server with ngrok and set the `helpServerURL` in the iOS app to `https://<your-ngrok>.ngrok.app/api/send-help` and `helpServerAPIKey` to the `API_KEY` value.

Request body expected (JSON):

{
  "toPhone": "2783xxxxxxx",
  "fullMessage": "Help request: FIRE - Name: ..."
}

The server will POST to the WhatsApp Cloud API and return the API response.

Security:
- Don't commit your `.env` file.
- Use HTTPS and a proper auth scheme in production.
- Use Meta's official Business API or an approved provider for production messaging.
