# Changes needed for the Discord bot to support per-conversation settings

# 1. Update the SyncedConversation model in discord_bot_sync_api.py

"""
class SyncedConversation(BaseModel):
    id: str
    title: str
    messages: List[SyncedMessage]
    created_at: datetime.datetime
    updated_at: datetime.datetime
    model_id: str
    sync_source: str = "discord"  # "discord" or "flutter"
    last_synced_at: Optional[datetime.datetime] = None
    
    # Conversation-specific settings
    reasoning_enabled: bool = False
    reasoning_effort: str = "medium"  # "low", "medium", "high"
    temperature: float = 0.7
    max_tokens: int = 1000
    web_search_enabled: bool = False
    system_message: Optional[str] = None
"""

# 2. Update the save_discord_conversation function in discord_bot_sync_api.py

"""
def save_discord_conversation(
    user_id: str, 
    messages: List[Dict[str, Any]], 
    model_id: str = "openai/gpt-3.5-turbo",
    reasoning_enabled: bool = False,
    reasoning_effort: str = "medium",
    temperature: float = 0.7,
    max_tokens: int = 1000,
    web_search_enabled: bool = False,
    system_message: Optional[str] = None
):
    # Convert messages to the synced format
    synced_messages = []
    for msg in messages:
        role = msg.get("role", "")
        if role not in ["user", "assistant", "system"]:
            continue
            
        synced_messages.append(SyncedMessage(
            content=msg.get("content", ""),
            role=role,
            timestamp=datetime.datetime.now(),
            reasoning=msg.get("reasoning"),
            usage_data=msg.get("usage_data")
        ))
    
    # Create a unique ID for this conversation
    conv_id = f"discord_{user_id}_{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}"
    
    # Create the synced conversation
    synced_conv = SyncedConversation(
        id=conv_id,
        title="Discord Conversation",
        messages=synced_messages,
        created_at=datetime.datetime.now(),
        updated_at=datetime.datetime.now(),
        model_id=model_id,
        sync_source="discord",
        reasoning_enabled=reasoning_enabled,
        reasoning_effort=reasoning_effort,
        temperature=temperature,
        max_tokens=max_tokens,
        web_search_enabled=web_search_enabled,
        system_message=system_message
    )
    
    # Add to storage
    if user_id not in user_conversations:
        user_conversations[user_id] = []
    
    user_conversations[user_id].append(synced_conv)
    save_conversations()
    
    return synced_conv
"""

# 3. Update the _get_ai_response method in your ai_cog.py

"""
async def _get_ai_response(self, user_id: int, prompt: str, system_prompt: str = None):
    # Get user settings
    settings = self._get_user_settings(user_id)
    
    # Initialize conversation history if it doesn't exist
    if user_id not in self.conversation_history:
        self.conversation_history[user_id] = []
        
        # Add system message if provided
        if system_prompt:
            self.conversation_history[user_id].append({
                "role": "system",
                "content": system_prompt
            })
    
    # Add user message to history
    self.conversation_history[user_id].append({
        "role": "user",
        "content": prompt
    })
    
    # Prepare messages for API request
    messages = self.conversation_history[user_id].copy()
    
    try:
        # Get response from API
        response = await self._call_ai_api(
            messages=messages,
            model=settings["model"],
            temperature=settings.get("temperature", 0.7),
            max_tokens=settings.get("max_tokens", 1000),
            reasoning_enabled=settings.get("reasoning_enabled", False),
            reasoning_effort=settings.get("reasoning_effort", "medium"),
            web_search_enabled=settings.get("web_search_enabled", False)
        )
        
        # Extract content and reasoning
        content = response["choices"][0]["message"]["content"]
        reasoning = response["choices"][0]["message"].get("reasoning")
        
        # Add assistant response to history
        assistant_message = {
            "role": "assistant",
            "content": content
        }
        
        if reasoning:
            assistant_message["reasoning"] = reasoning
            
        if "usage" in response:
            assistant_message["usage_data"] = response["usage"]
            
        self.conversation_history[user_id].append(assistant_message)
        
        # Save conversation to sync storage
        save_discord_conversation(
            str(user_id), 
            self.conversation_history[user_id],
            settings["model"],
            settings.get("reasoning_enabled", False),
            settings.get("reasoning_effort", "medium"),
            settings.get("temperature", 0.7),
            settings.get("max_tokens", 1000),
            settings.get("web_search_enabled", False),
            system_prompt
        )
        
        # Return the final response
        final_response = content
        if reasoning and settings.get("show_reasoning", False):
            final_response = f"{content}\n\n**Reasoning:**\n{reasoning}"
            
        return final_response
        
    except Exception as e:
        error_message = f"Error: {str(e)}"
        logger.error(error_message)
        return error_message
"""

# 4. Add a command to update conversation settings

"""
@commands.command(name="aisettings")
async def update_ai_settings(self, ctx: commands.Context, setting: str = None, value: str = None):
    \"\"\"Update AI settings for your conversations
    
    Examples:
    !aisettings - Show current settings
    !aisettings temperature 0.8 - Set temperature to 0.8
    !aisettings reasoning on - Enable reasoning
    !aisettings web_search on - Enable web search
    \"\"\"
    user_id = ctx.author.id
    settings = self._get_user_settings(user_id)
    
    if setting is None or value is None:
        # Show current settings
        settings_msg = "**Current AI Settings:**\\n"
        settings_msg += f"- Model: `{settings.get('model', 'openai/gpt-3.5-turbo')}`\\n"
        settings_msg += f"- Temperature: `{settings.get('temperature', 0.7)}`\\n"
        settings_msg += f"- Max Tokens: `{settings.get('max_tokens', 1000)}`\\n"
        settings_msg += f"- Reasoning: `{'Enabled' if settings.get('reasoning_enabled', False) else 'Disabled'}`\\n"
        settings_msg += f"- Reasoning Effort: `{settings.get('reasoning_effort', 'medium')}`\\n"
        settings_msg += f"- Web Search: `{'Enabled' if settings.get('web_search_enabled', False) else 'Disabled'}`\\n"
        
        await ctx.send(settings_msg)
        return
        
    # Update the specified setting
    if setting.lower() == "temperature":
        try:
            temp = float(value)
            if 0 <= temp <= 2:
                settings["temperature"] = temp
                await ctx.send(f"Temperature set to {temp}")
            else:
                await ctx.send("Temperature must be between 0 and 2")
        except ValueError:
            await ctx.send("Temperature must be a number")
            
    elif setting.lower() == "max_tokens" or setting.lower() == "tokens":
        try:
            tokens = int(value)
            if 100 <= tokens <= 4000:
                settings["max_tokens"] = tokens
                await ctx.send(f"Max tokens set to {tokens}")
            else:
                await ctx.send("Max tokens must be between 100 and 4000")
        except ValueError:
            await ctx.send("Max tokens must be a number")
            
    elif setting.lower() == "reasoning":
        if value.lower() in ["on", "true", "yes", "enable", "enabled"]:
            settings["reasoning_enabled"] = True
            await ctx.send("Reasoning enabled")
        elif value.lower() in ["off", "false", "no", "disable", "disabled"]:
            settings["reasoning_enabled"] = False
            await ctx.send("Reasoning disabled")
        else:
            await ctx.send("Value must be 'on' or 'off'")
            
    elif setting.lower() == "reasoning_effort" or setting.lower() == "effort":
        if value.lower() in ["low", "medium", "high"]:
            settings["reasoning_effort"] = value.lower()
            await ctx.send(f"Reasoning effort set to {value.lower()}")
        else:
            await ctx.send("Reasoning effort must be 'low', 'medium', or 'high'")
            
    elif setting.lower() == "web_search" or setting.lower() == "search":
        if value.lower() in ["on", "true", "yes", "enable", "enabled"]:
            settings["web_search_enabled"] = True
            await ctx.send("Web search enabled")
        elif value.lower() in ["off", "false", "no", "disable", "disabled"]:
            settings["web_search_enabled"] = False
            await ctx.send("Web search disabled")
        else:
            await ctx.send("Value must be 'on' or 'off'")
            
    elif setting.lower() == "system" or setting.lower() == "system_message":
        # Special case for system message - use the rest of the command as the message
        system_message = ctx.message.content.split(maxsplit=2)[2] if len(ctx.message.content.split(maxsplit=2)) > 2 else ""
        settings["system_message"] = system_message
        await ctx.send(f"System message updated: {system_message}")
        
    else:
        await ctx.send(f"Unknown setting: {setting}")
        
    # Save the updated settings
    self._save_user_settings(user_id, settings)
"""

# 5. Add methods to get and save user settings

"""
def _get_user_settings(self, user_id: int) -> Dict[str, Any]:
    \"\"\"Get settings for a user, with defaults if not set\"\"\"
    if not hasattr(self, 'user_settings'):
        self.user_settings = {}
        
    if user_id not in self.user_settings:
        # Default settings
        self.user_settings[user_id] = {
            "model": "openai/gpt-3.5-turbo",
            "temperature": 0.7,
            "max_tokens": 1000,
            "reasoning_enabled": False,
            "reasoning_effort": "medium",
            "web_search_enabled": False,
            "system_message": None
        }
        
    return self.user_settings[user_id]
    
def _save_user_settings(self, user_id: int, settings: Dict[str, Any]):
    \"\"\"Save settings for a user\"\"\"
    if not hasattr(self, 'user_settings'):
        self.user_settings = {}
        
    self.user_settings[user_id] = settings
    
    # Persist settings to disk
    try:
        with open(f"user_settings.json", "w") as f:
            json.dump(self.user_settings, f, indent=2, default=str)
    except Exception as e:
        logger.error(f"Error saving user settings: {e}")
"""

# 6. Load user settings on cog initialization

"""
def __init__(self, bot):
    self.bot = bot
    self.conversation_history = {}
    self.user_settings = {}
    
    # Load user settings from disk
    try:
        if os.path.exists("user_settings.json"):
            with open("user_settings.json", "r") as f:
                self.user_settings = json.load(f)
    except Exception as e:
        logger.error(f"Error loading user settings: {e}")
"""
