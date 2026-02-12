# Overview

This is a full-stack web application using a React frontend and Express backend, built with TypeScript throughout. The project follows a monorepo structure with shared code between client and server. It's currently a starter/boilerplate state with a users table defined but no application-specific features or routes implemented yet. The frontend uses shadcn/ui components with Tailwind CSS, and the backend is configured to use PostgreSQL via Drizzle ORM.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Directory Structure
- **`client/`** — React frontend (Vite-powered SPA)
- **`server/`** — Express backend (API server + static file serving in production)
- **`shared/`** — Shared code between client and server (database schema, types)
- **`scripts/`** — Miscellaneous scripts (contains unrelated shell script documentation)
- **`script/`** — Build script for production bundling
- **`migrations/`** — Drizzle database migration files (output directory)

### Frontend Architecture
- **Framework**: React with TypeScript
- **Bundler**: Vite (dev server with HMR proxied through Express)
- **Routing**: Wouter (lightweight client-side router)
- **State Management**: TanStack React Query for server state
- **UI Components**: shadcn/ui (new-york style) built on Radix UI primitives
- **Styling**: Tailwind CSS with CSS variables for theming (light/dark mode support)
- **Forms**: React Hook Form with Zod resolvers via `@hookform/resolvers`
- **Path aliases**: `@/` maps to `client/src/`, `@shared/` maps to `shared/`

### Backend Architecture
- **Framework**: Express 5 on Node.js
- **Runtime**: tsx for development, esbuild for production bundling
- **API Pattern**: All API routes should be prefixed with `/api`
- **Storage Layer**: Abstracted via `IStorage` interface in `server/storage.ts`. Currently uses in-memory storage (`MemStorage`), designed to be swapped for database-backed implementation
- **Session Support**: `connect-pg-simple` and `express-session` are available as dependencies
- **Dev/Prod Split**: In development, Vite middleware serves the frontend. In production, pre-built static files are served from `dist/public`

### Database
- **ORM**: Drizzle ORM with PostgreSQL dialect
- **Schema Location**: `shared/schema.ts` — shared between client and server
- **Schema Push**: `npm run db:push` uses drizzle-kit to push schema to database
- **Connection**: Requires `DATABASE_URL` environment variable
- **Validation**: Uses `drizzle-zod` to generate Zod schemas from Drizzle table definitions
- **Current Schema**: Single `users` table with `id` (UUID, auto-generated), `username` (unique text), and `password` (text)

### Build System
- **Development**: `npm run dev` runs the Express server with tsx, Vite serves frontend via middleware
- **Production Build**: `npm run build` runs a custom build script that:
  1. Builds the client with Vite (output to `dist/public`)
  2. Bundles the server with esbuild (output to `dist/index.cjs`)
  3. Selectively bundles certain dependencies (allowlist) while externalizing others
- **Production Start**: `npm start` runs the built `dist/index.cjs` with Node

### Key Design Decisions
1. **Shared schema between client and server** — The `shared/` directory contains Drizzle schema definitions that generate both database tables and Zod validation schemas, ensuring type safety across the full stack
2. **Storage interface abstraction** — The `IStorage` interface allows swapping between in-memory storage (for development/testing) and database-backed storage without changing route handlers
3. **Express serves everything** — Both the API and the frontend are served from the same Express server, simplifying deployment. In development, Vite middleware handles the frontend with HMR

## External Dependencies

### Database
- **PostgreSQL** — Required. Connection string must be provided via `DATABASE_URL` environment variable
- **Drizzle ORM** — Database access layer with drizzle-kit for schema management

### Key NPM Packages
- **Express 5** — Web server framework
- **Vite** — Frontend build tool and dev server
- **React 18** — UI framework
- **TanStack React Query** — Async state management
- **shadcn/ui + Radix UI** — Component library (comprehensive set of UI primitives installed)
- **Tailwind CSS** — Utility-first CSS framework
- **Zod** — Schema validation
- **Wouter** — Client-side routing

### Replit-Specific Plugins
- `@replit/vite-plugin-runtime-error-modal` — Runtime error overlay
- `@replit/vite-plugin-cartographer` — Dev tooling (dev only)
- `@replit/vite-plugin-dev-banner` — Dev banner (dev only)