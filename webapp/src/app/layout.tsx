import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import './globals.css';
export const metadata: Metadata = { title: 'Vita — A little closer, every day', description: 'A quiet space for companionship, shared stories, and everyday moments.' };
export default function RootLayout({ children }: {
    children: ReactNode;
}) {
    return <html lang="zh-CN" suppressHydrationWarning><body>{children}</body></html>;
}
