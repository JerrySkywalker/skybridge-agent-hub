declare module "node:sqlite" {
  export const DatabaseSync: new (path: string) => {
    close(): void;
    exec(sql: string): void;
    prepare(sql: string): {
      all(...params: unknown[]): unknown[];
      get(...params: unknown[]): unknown;
      run(...params: unknown[]): unknown;
    };
  };
}
