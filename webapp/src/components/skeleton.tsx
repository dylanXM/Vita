import type { MessageKey } from '../lib/i18n';
type Props = { t: (key: MessageKey) => string; variant?: 'cards' | 'world' | 'chat' | 'form' | 'people' };
export default function Skeleton({ t, variant = 'cards' }: Props) {
    return <div className={`skeleton skeleton-${variant}`} role="status" aria-label={t('loading')} aria-busy="true"><div aria-hidden="true" className="skeleton-layout">
        {Array.from({ length: variant === 'world' ? 1 : variant === 'people' ? 3 : 4 }, (_, index) => <div className="skeleton-item" key={index}>
            {(variant === 'world' || variant === 'cards') && <div className="skeleton-block skeleton-image"/>}
            {variant === 'people' && <div className="skeleton-block skeleton-avatar"/>}
            <div className="skeleton-copy"><div className="skeleton-block skeleton-title"/><div className="skeleton-block skeleton-line"/><div className="skeleton-block skeleton-line skeleton-short"/>{variant === 'world' && <div className="skeleton-block skeleton-button"/>}</div>
        </div>)}
    </div></div>;
}
