import { webhookHandler } from '../_shared/xendit.ts';

Deno.serve(webhookHandler((name) => Deno.env.get(name)));
