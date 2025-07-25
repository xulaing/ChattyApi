// api/chatgpt.js 
export default async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).json({
            error: 'Method not allowed'
        });
    }
    const {
        prompt
    } = req.body;
    const apiKey = process.env.OPENAI_API_KEY;
    if (!prompt || !apiKey) {
        return res.status(400).json({
            error: 'Prompt or API key missing'
        });
    }
    try {
        const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
                model: 'gpt-3.5-turbo',
                messages: [{
                    role: 'user',
                    content: prompt
                }],
            }),
        });
        const data = await openaiResponse.json();
        if (data.choices && data.choices.length > 0) {
            return res.status(200).json({
                response: data.choices[0].message.content
            });
        } else {
            return res.status(500).json({
                error: 'No response from OpenAI'
            });
        }
    } catch (err) {
        return res.status(500).json({
            error: 'API error',
            details: err.message
        });
    }
}
