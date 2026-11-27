import { checkoutHandler } from '../_shared/xendit.ts';

Deno.serve(checkoutHandler((name) => Deno.env.get(name)));
