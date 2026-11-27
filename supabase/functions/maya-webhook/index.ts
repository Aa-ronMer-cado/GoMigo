import { webhookHandler } from '../_shared/maya.ts';

Deno.serve(webhookHandler((name) => Deno.env.get(name)));
