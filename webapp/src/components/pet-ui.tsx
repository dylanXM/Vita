'use client';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { ArrowRight, Droplets, Footprints, Heart, Moon, PawPrint, Utensils } from 'lucide-react';
import type { Entity } from '../lib/api';
import { productText, type MessageKey } from '../lib/i18n';
import { Media } from './companion-ui';
import PetRoom from './pet-room';

type T = (key: MessageKey) => string;
const careActions = [
    { key: 'pet', Icon: Heart },
    { key: 'drink', Icon: Droplets },
    { key: 'walk', Icon: Footprints },
    { key: 'rest', Icon: Moon },
    { key: 'feed', Icon: Utensils },
] as const;
const stats = ['hunger', 'hydration', 'happiness', 'energy', 'health'] as const;

export function PetCatalog({ breeds, t, open, adopt }: {
    breeds: Entity[];
    t: T;
    open: (pet: Entity) => void;
    adopt: (pet: Entity) => void;
}) {
    const reduced = useReducedMotion();
    return <div className="pet-gallery">{breeds.map((breed, index) => <motion.article
        key={breed.id} className="pet-gallery-card"
        initial={reduced ? false : { opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: reduced ? 0 : .3, delay: reduced ? 0 : Math.min(index, 5) * .05 }}
    >
        <div className="pet-gallery-art"><Media src={breed.avatar_url} alt={breed.name}/><span className="pet-gallery-mark" aria-hidden="true"><PawPrint size={18}/></span></div>
        <div className="pet-gallery-copy"><span className="eyebrow">{breed.species}</span><h2>{breed.name}</h2><p>{breed.description}</p>
            <motion.button className={`button full ${breed.adopted_companion_id ? 'primary' : ''}`}
                disabled={!breed.adopted_companion_id && !breed.can_adopt}
                whileTap={reduced ? undefined : { scale: .98 }}
                onClick={() => breed.adopted_companion_id ? open(breed) : adopt(breed)}
            >{breed.adopted_companion_id ? productText('aiPets.openHome', t) : t('adopt')}<ArrowRight size={16} aria-hidden="true"/></motion.button>
            {!breed.adopted_companion_id && !breed.can_adopt && <a className="pet-membership-link" href="#membership">{t('manage')}</a>}
        </div>
    </motion.article>)}</div>;
}

export function PetHome({ pet, state, action, busy, pending, t, care }: {
    pet: Entity;
    state: Entity;
    action: string;
    busy: boolean;
    pending: Entity | null;
    t: T;
    care: (kind: string) => Promise<void>;
}) {
    const reduced = useReducedMotion();
    const duration = reduced ? 0 : .3;
    return <motion.section className="pet-suite" aria-busy={busy}
        initial={reduced ? false : { opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration }}>
        <div className="pet-suite-stage"><PetRoom pet={{ ...pet, ...state }} action={action} t={t} onPet={() => { if (!busy && !pending) void care('pet'); }}/></div>
        <div className="pet-suite-panel">
            <header className="pet-suite-heading"><span className="eyebrow"><PawPrint size={15} aria-hidden="true"/>{t('pets')}</span><h2>{pet.adopted_companion_name || pet.name}</h2><p>{t('petWelcome')}</p></header>
            <div className="pet-vitals">{stats.map(key => {
                const value = Math.min(100, Math.max(0, Number(state[key]) || 0));
                return <div className="pet-vital" key={key}><div className="pet-vital-label"><span>{t(key)}</span><span>{value}<small> / 100</small></span></div>
                    <div className="pet-vital-track" role="progressbar" aria-label={t(key)} aria-valuemin={0} aria-valuemax={100} aria-valuenow={value}>
                        <motion.span initial={false} animate={{ scaleX: value / 100 }} transition={{ duration: reduced ? 0 : .5 }}/>
                    </div>
                </div>;
            })}</div>
            <div className="pet-care-controls">{careActions.map(({ key, Icon }) => <motion.button
                key={key} className={`pet-care-button ${key === 'feed' ? 'is-feed' : ''}`}
                disabled={busy || !!pending} whileTap={reduced ? undefined : { scale: .96 }}
                onClick={() => void care(key)}
            ><Icon size={20} strokeWidth={1.6} aria-hidden="true"/><span>{t(key)}</span>{key === 'feed' && <small>{state.feed_coin_cost} {t('credits')}</small>}</motion.button>)}</div>
            <div className="pet-care-feedback" role="status"><AnimatePresence mode="wait" initial={false}>
                <motion.span key={busy ? 'loading' : action} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: reduced ? 0 : .15 }}>
                    {t(busy ? 'loading' : 'petWelcome')}
                </motion.span>
            </AnimatePresence></div>
        </div>
        <AnimatePresence initial={false}>{pending && <motion.div className="access-banner pet-care-pending" key="pending"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration }}>
            <p>{t(busy ? 'loading' : 'requestUnconfirmed')}</p><button className="button primary" disabled={busy} onClick={() => void care(pending.kind)}>{t('retry')}</button>
        </motion.div>}</AnimatePresence>
    </motion.section>;
}
