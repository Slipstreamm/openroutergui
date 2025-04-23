# Discord Sync Integration

This document explains how to set up the Discord OAuth integration between your Flutter app and Discord bot.

## Overview

The integration allows users to:
1. Log in with their Discord account
2. Sync conversations between the Flutter app and Discord bot
3. Import conversations from Discord to the Flutter app
4. Export conversations from the Flutter app to Discord

## Setup Instructions

### 1. Discord Developer Portal Setup

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Click "New Application" and give it a name (e.g., "OpenRouter GUI")
3. Go to the "OAuth2" section
4. Add a redirect URL: `https://slipstreamm.dev/discordapi/auth`
5. In the OAuth2 settings, make sure "PKCE" is enabled
6. Copy the "Client ID" - you'll need this for the Flutter app

### 2. Flutter App Setup

1. Open `lib/services/discord_oauth_service.dart`
2. Replace the placeholder Client ID with your actual Client ID from the Discord Developer Portal:
   ```dart
   static const String clientId = '123456789012345678'; // Replace with your actual Client ID
   ```

3. Open `lib/services/sync_service.dart`
4. The bot API URL is already set to the production endpoint:
   ```dart
   static const String botApiUrl = 'https://slipstreamm.dev/discordapi';
   ```

### 3. Discord Bot Setup

1. Copy the `discord_bot_sync_api.py` file to your Discord bot project
2. Install the required dependencies:
   ```bash
   pip install fastapi uvicorn pydantic
   ```

3. Add the following code to your main bot file (e.g., `bot.py`):
   ```python
   import threading
   import uvicorn

   def run_api():
       uvicorn.run("discord_bot_sync_api:app", host="0.0.0.0", port=8000)

   # Start the API in a separate thread
   api_thread = threading.Thread(target=run_api)
   api_thread.daemon = True
   api_thread.start()
   ```

4. Modify your `ai_cog.py` file to integrate with the sync API:
   ```python
   from discord_bot_sync_api import save_discord_conversation, load_conversations, user_conversations

   # In your _get_ai_response method, after getting the response:
   messages = conversation_history[user_id]
   save_discord_conversation(str(user_id), messages, settings["model"])

   # Add a command to view sync status:
   @commands.command(name="aisync")
   async def ai_sync_status(self, ctx: commands.Context):
       user_id = str(ctx.author.id)
       if user_id not in user_conversations or not user_conversations[user_id]:
           await ctx.reply("You don't have any synced conversations.")
           return

       synced_count = len(user_conversations[user_id])
       await ctx.reply(f"You have {synced_count} synced conversations that can be accessed from the Flutter app.")
   ```

### 4. Network Configuration

1. The app is already configured to use the production endpoint at `https://slipstreamm.dev/discordapi`
2. Make sure your Discord bot is running and the API is accessible at this URL
3. If you need to test locally, you can change the URL in `sync_service.dart` to your local endpoint

## Usage

1. In the Flutter app, go to Settings > Discord Integration
2. Click "Login with Discord" to authenticate
3. Use the "Sync Conversations" button to sync conversations
4. Use the "Import from Discord" button to import conversations from Discord

## Troubleshooting

- **Authentication Issues**: Make sure the Client ID is correct and the redirect URL is properly configured
- **Sync Issues**: Check that the bot API URL is accessible and the API is running
- **Import/Export Issues**: Verify that the Discord bot has saved conversations to sync

## Security Considerations

- The integration uses Discord OAuth for authentication, ensuring only authorized users can access their conversations
- All API requests require a valid Discord token
- The API verifies the token with Discord for each request
- Consider adding rate limiting and additional security measures for production use
