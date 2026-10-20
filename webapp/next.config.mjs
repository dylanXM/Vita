/** @type {import('next').NextConfig} */
const nextConfig = {
  // 'standalone' is only needed for the self-hosted Docker image. On Vercel
  // it breaks the build (missing .next/next-server.js.nft.json), so skip it there.
  ...(process.env.VERCEL ? {} : { output: 'standalone' }),
  devIndicators: false,
}

export default function config(phase) {
  if (phase === PHASE_DEVELOPMENT_SERVER) {
    return {
      ...nextConfig,
      skipTrailingSlashRedirect: true,
      async rewrites() {
        const backend = (process.env.NEXT_PUBLIC_VITA_API_URL || 'http://127.0.0.1:8260').replace(/\/$/, '')
        return [
          { source: '/v1/:path*/', destination: `${backend}/v1/:path*/` },
          { source: '/v1/:path*', destination: `${backend}/v1/:path*` },
        ]
      },
    }
  }
  return nextConfig
}
import { PHASE_DEVELOPMENT_SERVER } from 'next/constants.js'

