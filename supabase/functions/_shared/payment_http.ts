export type Fetch = typeof fetch;
export type Settings = (name: string) => string | undefined;
export type RecordData = Record<string, unknown>;

export const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export class PaymentError extends Error {
  readonly status: number;
  readonly code?: string;

  constructor(status: number, message: string, code?: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function record(value: unknown): RecordData {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as RecordData
    : {};
}

export function secureUrl(value: unknown): URL | undefined {
  if (typeof value !== 'string') return;
  try {
    const url = new URL(value);
    if (url.protocol === 'https:' && !url.username && !url.password) return url;
  } catch {
    return undefined;
  }
}

export function json(value: RecordData, status = 200): Response {
  return Response.json(value, { status, headers: { ...cors, 'Cache-Control': 'no-store' } });
}

export async function handle(operation: () => Promise<Response>): Promise<Response> {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof PaymentError) {
      return json({ error: error.message, ...(error.code ? { code: error.code } : {}) }, error.status);
    }
    return json({ error: 'Test payment service is temporarily unavailable.' }, 503);
  }
}

export function database(settings: Settings, request: Fetch, timeout = 8000) {
  const base = settings('SUPABASE_URL');
  const keys = settings('SUPABASE_SECRET_KEYS');
  const key = (keys && record(JSON.parse(keys)).default) || settings('SUPABASE_SERVICE_ROLE_KEY');
  if (!base || typeof key !== 'string' || !key) {
    throw new PaymentError(503, 'The test payment backend is unavailable.');
  }
  const headers: Record<string, string> = { apikey: key };
  if (!key.startsWith('sb_secret_')) headers.Authorization = `Bearer ${key}`;

  return {
    async travelerId(authorization: string | null): Promise<string> {
      if (!authorization || !/^Bearer \S+$/i.test(authorization)) {
        throw new PaymentError(401, 'Sign in to manage test payments.');
      }
      const response = await request(`${base}/auth/v1/user`, {
        headers: { ...headers, Authorization: authorization },
        signal: AbortSignal.timeout(timeout),
      });
      if (response.status === 401 || response.status === 403) {
        throw new PaymentError(401, 'Sign in to manage test payments.');
      }
      if (!response.ok) throw new PaymentError(503, 'Could not verify the session.');
      const user = record(await response.json());
      if (typeof user.id !== 'string' || !uuid.test(user.id) || user.is_anonymous === true) {
        throw new PaymentError(401, 'Sign in to manage test payments.');
      }
      return user.id;
    },
    async rpc<T>(name: string, args: RecordData): Promise<T> {
      const response = await request(`${base}/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(timeout),
      });
      const body = await response.json();
      if (!response.ok) {
        switch (record(body).code) {
          case 'GM404':
            throw new PaymentError(404, 'Booking unavailable.');
          case 'GM409':
            throw new PaymentError(409, 'This booking is no longer eligible for checkout.');
          default:
            throw new PaymentError(503, 'Could not save or read the test payment. Try again.');
        }
      }
      return body as T;
    },
  };
}

