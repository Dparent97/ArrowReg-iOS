const SSE_HEADERS = {
  'Content-Type': 'text/event-stream',
  'Cache-Control': 'no-cache',
  Connection: 'keep-alive',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

export function createSSEStream() {
  const encoder = new TextEncoder();
  let controller;
  const stream = new ReadableStream({
    start(ctrl) {
      controller = ctrl;
    }
  });

  function send(type, data) {
    const payload = `data: ${JSON.stringify({ type, data })}\n\n`;
    controller.enqueue(encoder.encode(payload));
  }

  function close() {
    controller.close();
  }

  return { stream, send, close };
}

export function sseResponse(handler) {
  const { stream, send, close } = createSSEStream();

  (async () => {
    try {
      await handler({ send, close });
    } catch (err) {
      send('error', err.message);
      close();
    }
  })();

  return new Response(stream, { headers: SSE_HEADERS });
}

export { SSE_HEADERS };
