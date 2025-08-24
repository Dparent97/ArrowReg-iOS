export function startStream(handler) {
  const encoder = new TextEncoder();
  const readable = new ReadableStream({
    async start(controller) {
      await handler(controller, encoder);
    }
  });

  return new Response(readable, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Allow-Methods': 'POST, OPTIONS'
    }
  });
}

export function sendEvent(controller, encoder, type, data) {
  controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type, data })}\n\n`));
}

export function closeStream(controller) {
  controller.close();
}
