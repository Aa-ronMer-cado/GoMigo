import { checkoutHandler } from '../_shared/paymongo.ts';

Deno.serve(checkoutHandler((name) => Deno.env.get(name)));
