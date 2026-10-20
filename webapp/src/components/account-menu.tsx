'use client';
import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { ArrowLeft, Check, ChevronRight, Languages, LogOut, MessageSquare, Moon, Pencil, Settings2, UserRound } from 'lucide-react';
import { Media } from './companion-ui';
import type { Entity } from '../lib/api';
import { localeNames, type Locale, type MessageKey } from '../lib/i18n';
export type Theme = 'system' | 'light' | 'dark';
type Props = {
    t: (key: MessageKey) => string;
    locale: Locale;
    setLocale: (locale: Locale) => void;
    theme: Theme;
    setTheme: (theme: Theme) => void;
    authenticated: boolean;
    me: Entity | null;
    balance?: number;
    login: () => void;
    edit: () => void;
    feedback: () => void;
    logout: () => void;
};
export default function AccountMenu({ t, locale, setLocale, theme, setTheme, authenticated, me, balance, login, edit, feedback, logout }: Props) {
    const id = useId();
    const trigger = useRef<HTMLButtonElement>(null);
    const menu = useRef<HTMLDivElement>(null);
    const [open, setOpen] = useState(false);
    const [panel, setPanel] = useState<'language' | 'theme' | null>(null);
    const name = me?.nickname || me?.email || t('login');
    const position = useCallback(() => {
        const button = trigger.current, element = menu.current;
        if (!button || !element) return;
        const bounds = button.getBoundingClientRect();
        const sidebar = button.closest('aside')?.getBoundingClientRect() || bounds;
        const left = document.documentElement.dir === 'rtl' ? sidebar.left - element.offsetWidth - 8 : sidebar.right + 8;
        const bottom = Math.max(12, window.innerHeight - bounds.bottom);
        element.style.left = `${Math.max(12, Math.min(left, window.innerWidth - element.offsetWidth - 12))}px`;
        element.style.bottom = `${bottom}px`;
        element.style.maxHeight = `${Math.max(0, window.innerHeight - bottom - 12)}px`;
    }, []);
    useEffect(() => {
        if (!open) return;
        position();
        window.addEventListener('resize', position);
        window.addEventListener('scroll', position, true);
        return () => { window.removeEventListener('resize', position); window.removeEventListener('scroll', position, true); };
    }, [open, position]);
    function action(callback: () => void) { menu.current?.hidePopover(); callback(); }
    const avatar = authenticated && me?.avatar_url ? <Media className="avatar" src={me.avatar_url} alt=""/> : <span className="initial">{authenticated ? name.slice(0, 1).toUpperCase() : <UserRound size={17}/>}</span>;
    return <>
        <button ref={trigger} type="button" className={`profile-link ${open ? 'selected' : ''}`} popoverTarget={id} aria-haspopup="menu" aria-expanded={open} aria-controls={id}>{avatar}<span>{name}<small>{authenticated ? `${balance ?? '—'} ${t('credits')}` : 'Vita'}</small></span><Settings2 size={17}/></button>
        <div ref={menu} id={id} popover="auto" className="account-menu" onToggle={event => { const visible = event.newState === 'open'; setOpen(visible); if (visible) position(); else setPanel(null); }} onKeyDown={event => {
            if (event.key === 'Escape' && panel) { event.preventDefault(); event.stopPropagation(); setPanel(null); return; }
            if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
            event.preventDefault();
            const buttons = Array.from(event.currentTarget.querySelectorAll<HTMLButtonElement>('button:not(:disabled)'));
            const index = buttons.indexOf(document.activeElement as HTMLButtonElement);
            const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowUp' ? -1 : 1) + buttons.length) % buttons.length;
            buttons[next]?.focus();
        }}>
            <div className="account-menu-user">{avatar}<span><strong>{name}</strong><small>{t(authenticated ? 'signedIn' : 'loginRequired')}</small></span></div>
            {panel ? <div role="menu" aria-label={t(panel === 'language' ? 'language' : 'switchTheme')}>
                <button className="account-menu-item account-menu-back" role="menuitem" onClick={() => setPanel(null)}><ArrowLeft size={17}/>{t(panel === 'language' ? 'language' : 'switchTheme')}</button>
                {panel === 'language' ? Object.entries(localeNames).map(([key, label]) => <button className="account-menu-item" role="menuitemradio" aria-checked={locale === key} key={key} onClick={() => { setLocale(key as Locale); setPanel(null); }}><span>{label}</span>{locale === key && <Check size={16}/>}</button>) : (['system', 'light', 'dark'] as const).map(value => <button className="account-menu-item" role="menuitemradio" aria-checked={theme === value} key={value} onClick={() => { setTheme(value); setPanel(null); }}><span>{t(value === 'system' ? 'followSystem' : value)}</span>{theme === value && <Check size={16}/>}</button>)}
            </div> : <div role="menu" aria-label={t('account')}>
                {authenticated && <><button className="account-menu-item" role="menuitem" onClick={() => action(edit)}><Pencil size={17}/><span>{t('editProfile')}</span></button><button className="account-menu-item" role="menuitem" onClick={() => action(feedback)}><MessageSquare size={17}/><span>{t('menuFeedback')}</span></button></>}
                <button className="account-menu-item" role="menuitem" aria-haspopup="menu" onClick={() => setPanel('language')}><Languages size={17}/><span>{t('language')}</span><small>{localeNames[locale]}</small><ChevronRight size={14}/></button>
                <button className="account-menu-item" role="menuitem" aria-haspopup="menu" onClick={() => setPanel('theme')}><Moon size={17}/><span>{t('switchTheme')}</span><small>{t(theme === 'system' ? 'followSystem' : theme)}</small><ChevronRight size={14}/></button>
                <div className="account-menu-separator"/>
                <button className="account-menu-item" role="menuitem" onClick={() => action(authenticated ? logout : login)}><LogOut size={17}/><span>{t(authenticated ? 'logout' : 'login')}</span></button>
            </div>}
        </div>
    </>;
}
