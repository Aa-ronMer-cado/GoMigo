import { webhookHandler } from '../_shared/paymongo.ts';

Deno.serve(webhookHandler((name) => Deno.env.get(name)));
