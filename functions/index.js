const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const axios = require("axios");

// Declare secret
const DISCORD_TOKEN = defineSecret("DISCORD_TOKEN");

exports.createDiscordChannel = onRequest(
  { secrets: [DISCORD_TOKEN] },
  async (req, res) => {
    const { guildId, channelName, categoryId } = req.body;

    if (!guildId || !channelName || !categoryId) {
      return res.status(400).send("Missing required parameters.");
    }

    try {
      const response = await axios.post(
        `https://discord.com/api/v10/guilds/${guildId}/channels`,
        {
          name: channelName,
          type: 0,
          parent_id: categoryId,
        },
        {
          headers: {
            Authorization: `Bot ${DISCORD_TOKEN.value()}`,
            "Content-Type": "application/json",
          },
        }
      );

      return res.status(200).send({
        message: `✅ Created channel: ${response.data.name}`,
        channelId: response.data.id,
      });
    } catch (error) {
      const message = error.response?.data || error.message;
      console.error("❌ Discord API error:", message);
      return res.status(500).json({ error: message });
    }
  }
);

exports.createDiscordEvent = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  const {
    guildId,
    name,
    description,
    scheduledStartTime,
    scheduledEndTime,
    entityType,           // 1=Stage, 2=Voice, 3=External
    privacyLevel,         // usually 2
    channelId,            // For non-external
    entityMetadata        // { location: ... }
  } = req.body;

  // Basic required checks (don't require channelId unless it's a channel event)
  if (!guildId || !name || !scheduledStartTime) {
    return res.status(400).json({ error: "Missing required parameters: guildId, name, or scheduledStartTime." });
  }

  // Discord API payload
  const payload = {
    name,
    description: description || "",
    scheduled_start_time: new Date(scheduledStartTime).toISOString(),
    privacy_level: privacyLevel || 2,   // default to GUILD_ONLY
    entity_type: entityType || 3        // default to EXTERNAL
  };

  // Add channel_id and metadata as needed
  if (payload.entity_type === 3) { // EXTERNAL
    if (!scheduledEndTime || !entityMetadata?.location) {
      return res.status(400).json({ error: "Missing scheduledEndTime or entityMetadata.location for external event." });
    }
    payload.scheduled_end_time = new Date(scheduledEndTime).toISOString();
    payload.entity_metadata = entityMetadata;
  } else {
    if (!channelId) {
      return res.status(400).json({ error: "Missing channelId for channel event." });
    }
    payload.channel_id = channelId;
  }

  try {
    const response = await axios.post(
      `https://discord.com/api/v10/guilds/${guildId}/scheduled-events`,
      payload,
      {
        headers: {
          Authorization: `Bot ${DISCORD_TOKEN.value()}`,
          "Content-Type": "application/json"
        }
      }
    );

    return res.status(200).send({
      message: `✅ Created event: ${response.data.name}`,
      eventId: response.data.id
    });
  } catch (error) {
    const message = error.response?.data || error.message;
    console.error("❌ Discord API error:", message);
    return res.status(500).json({ error: message });
  }
});

  
exports.updateDiscordEvent = onRequest({ secrets: [DISCORD_TOKEN] }, async (req, res) => {
  const { guildId, eventId, ...updateFields } = req.body;
  if (!guildId || !eventId) {
    return res.status(400).send("Missing guildId or eventId.");
  }
  try {
    const response = await axios.patch(
      `https://discord.com/api/v10/guilds/${guildId}/scheduled-events/${eventId}`,
      updateFields,
      {
        headers: {
          Authorization: `Bot ${DISCORD_TOKEN.value()}`,
          "Content-Type": "application/json"
        }
      }
    );
    return res.status(200).send({
      message: `✅ Updated event: ${response.data.name}`,
      eventId: response.data.id
    });
  } catch (error) {
    const message = error.response?.data || error.message;
    return res.status(500).json({ error: message });
  }
});
