// Guard the workflow's media migration/reapply/SQL proof sessions too.
import { readFileSync } from 'node:fs';
import { createDisposableMediaPsql } from './disposable_media_target.mjs';
const database = createDisposableMediaPsql(process.env.DATABASE_URL);
const [file, ...extra] = process.argv.slice(2);
if (extra.length || typeof file !== 'string' ||
    !/^supabase\/(?:migrations|tests)\/[A-Za-z0-9_]+\.sql$/.test(file)) {
  throw new Error('Expected one repository media SQL file');
}
process.stdout.write(database.sql(readFileSync(file, 'utf8')));
