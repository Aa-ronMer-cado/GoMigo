import { checkoutHandler } from '../_shared/maya.ts';

Deno.serve(checkoutHandler((name) => Deno.env.get(name)));
