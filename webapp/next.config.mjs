/** @type {import('next').NextConfig} */
const nextConfig = {
  // 'standalone' is only needed for the self-hosted Docker image. On Vercel
  // it breaks the build (missing .next/next-server.js.nft.json), so skip it there.
  ...(process.env.VERCEL ? {} : { output: 'standalone' }),
  devIndicators: false,
}

export default nextConfig
