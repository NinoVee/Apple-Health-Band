const SYSTEM_PROMPT = `You are a health data assistant inside a smart band companion app. You'll be given a text summary of the user's recent Apple Health data and a conversation. Answer questions about trends and patterns in that data. You are not a medical professional: never diagnose conditions or prescribe treatment, and tell the user to consult a doctor for any medical concern. Keep answers concise.`;

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const sharedSecret = process.env.RELAY_SHARED_SECRET;
  if (sharedSecret && req.headers['x-app-secret'] !== sharedSecret) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const { provider, healthContext, messages } = req.body || {};
  if (!provider || !Array.isArray(messages)) {
    res.status(400).json({ error: 'Missing provider or messages' });
    return;
  }

  try {
    const reply =
      provider === 'chatgpt'
        ? await callChatGPT(healthContext, messages)
        : await callClaude(healthContext, messages);
    res.status(200).json({ reply });
  } catch (error) {
    res.status(502).json({ error: error.message || 'Upstream request failed' });
  }
}

async function callClaude(healthContext, messages) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('Server is not configured with ANTHROPIC_API_KEY');

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: process.env.CLAUDE_MODEL || 'claude-sonnet-4-5',
      max_tokens: 1024,
      system: `${SYSTEM_PROMPT}\n\nHealth data summary:\n${healthContext || 'No data provided.'}`,
      messages: messages.map((m) => ({ role: m.role, content: m.content }))
    })
  });

  if (!response.ok) {
    throw new Error(`Claude API error (${response.status}): ${await response.text()}`);
  }
  const data = await response.json();
  return (data.content || []).map((block) => block.text || '').join('');
}

async function callChatGPT(healthContext, messages) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('Server is not configured with OPENAI_API_KEY');

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
      messages: [
        { role: 'system', content: `${SYSTEM_PROMPT}\n\nHealth data summary:\n${healthContext || 'No data provided.'}` },
        ...messages.map((m) => ({ role: m.role, content: m.content }))
      ]
    })
  });

  if (!response.ok) {
    throw new Error(`OpenAI API error (${response.status}): ${await response.text()}`);
  }
  const data = await response.json();
  return data.choices?.[0]?.message?.content || '';
}
