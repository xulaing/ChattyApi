// api/chatty.js 
export const config = {
    runtime: 'edge', // this is a pre-requisite
};

const CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export default async function handler(req, res) {
    if (req.method === 'OPTIONS') {
        return new Response(null, {
            status: 204,
            headers: CORS_HEADERS,
        });
    }

    if (req.method !== 'POST') {
        return new Response(null, {
            status: 405,
            headers: CORS_HEADERS,
        });
    }
    const {
        prompt
    } = await req.json();
    const apiKey = process.env.OPENAI_API_KEY;
    if (!prompt || !apiKey) {
        return new Response(null, {
            status: 400,
            headers: CORS_HEADERS,
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
            return new Response(JSON.stringify({
                response: json.choices[0].messages.content
            }), {
                status: 204,
                headers: CORS_HEADERS,
            });
        } else {
            return new Response(null, {
                status: 500,
                headers: CORS_HEADERS,
            });
        }
    } catch (err) {
        return new Response(null, {
            status: 500,
            headers: CORS_HEADERS,
        });
    }
}
