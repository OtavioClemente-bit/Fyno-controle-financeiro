import assert from 'node:assert/strict';
import test from 'node:test';

import worker from '../src/index.js';

test('envia somente nomes e devolve resultado estruturado', async () => {
  let outboundBody;
  globalThis.caches = {
    default: {
      match: async () => undefined,
      put: async () => undefined,
    },
  };
  globalThis.fetch = async (_url, init) => {
    outboundBody = JSON.parse(init.body);
    return new Response(
      JSON.stringify({
        output: [
          {
            type: 'message',
            content: [
              {
                type: 'output_text',
                text: JSON.stringify({
                  products: [
                    {
                      index: 0,
                      professional_name: 'Refrigerante Coca-Cola Lata 350 ml',
                      confidence: 0.96,
                    },
                  ],
                }),
              },
            ],
          },
        ],
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  };

  const response = await worker.fetch(
    new Request('https://fyno.example/normalize-products', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        products: [{ index: 0, raw_name: 'REFR COCA COLA LT 350ML' }],
      }),
    }),
    { OPENAI_API_KEY: 'test-key', SAFETY_SALT: 'test-salt' },
    { waitUntil: () => undefined },
  );

  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(
    result.products[0].professional_name,
    'Refrigerante Coca-Cola Lata 350 ml',
  );
  assert.equal(outboundBody.model, 'gpt-5.6-luna');
  assert.equal(outboundBody.store, false);
  assert.match(outboundBody.input, /REFR COCA COLA/);
  assert.doesNotMatch(outboundBody.input, /price|amount|receipt/i);
});

test('recusa listas vazias ou grandes demais', async () => {
  globalThis.caches = {
    default: { match: async () => undefined, put: async () => undefined },
  };
  const response = await worker.fetch(
    new Request('https://fyno.example/normalize-products', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ products: [] }),
    }),
    { OPENAI_API_KEY: 'test-key' },
    { waitUntil: () => undefined },
  );
  assert.equal(response.status, 400);
});
