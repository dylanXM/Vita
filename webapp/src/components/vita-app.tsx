'use client';
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp, BookOpen, Check, Compass, Globe2, Heart, History, LogOut, Menu, MessageCircle, Moon, MoreHorizontal, PanelLeft, PawPrint, Plus, Search, Settings2, Sparkles, Sun, UserRound, X } from 'lucide-react';
import { api, ApiError, baseURL, items, safeURL, session, type Entity } from '../lib/api';
import GoogleSignIn from './google-sign-in';
import { exchangeGoogleCredential, type GoogleConsent } from '../lib/google-auth';
import { messages, type Locale, type MessageKey, productText } from '../lib/i18n';
type Section = 'world' | 'chat' | 'journey' | 'explore' | 'stories' | 'pets' | 'account';
type T = (key: MessageKey) => string;
const navigation = [{ id: 'world', Icon: Globe2 }, { id: 'chat', Icon: MessageCircle }, { id: 'journey', Icon: History }, { id: 'explore', Icon: Compass }] as const;
function useResource(path: string | null, revision = 0) {
    const [data, setData] = useState<any>(null);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const [retry, setRetry] = useState(0);
    useEffect(() => {
        setData(null);
        setError('');
        if (!path) {
            setLoading(false);
            return;
        }
        const controller = new AbortController();
        setLoading(true);
        api(path, { signal: controller.signal }).then(setData).catch(e => {
            if (!controller.signal.aborted)
                setError(e.message);
        }).finally(() => {
            if (!controller.signal.aborted)
                setLoading(false);
        });
        return () => controller.abort();
    }, [path, revision, retry]);
    return { data, error, loading, reload: () => setRetry(n => n + 1) };
}
function Status({ resource, t, children }: {
    resource: ReturnType<typeof useResource>;
    t: T;
    children: ReactNode;
}) {
    if (resource.loading)
        return <div className="state" role="status"><span className="spinner"/>{t('loading')}</div>;
    if (resource.error)
        return <div className="state" role="alert"><p>{resource.error}</p><button className="button" onClick={resource.reload}>{t('retry')}</button></div>;
    return <>{children}</>;
}
function Empty({ t, children }: {
    t: T;
    children?: ReactNode;
}) { return <div className="state empty"><Sparkles size={28}/><p>{t('empty')}</p>{children}</div>; }
function Media({ src, kind = 'image', alt = '', className = '' }: {
    src?: string;
    kind?: string;
    alt?: string;
    className?: string;
}) {
    const [url, setURL] = useState('');
    useEffect(() => {
        let active = true;
        let objectURL = '';
        const controller = new AbortController();
        const value = safeURL(src);
        setURL('');
        if (!value)
            return;
        const parsed = new URL(value, window.location.origin);
        if (parsed.pathname.startsWith('/v1/media/') || parsed.pathname.startsWith('/v1/encounters/media/')) {
            const headers: Record<string, string> = {};
            if (parsed.origin === new URL(baseURL || window.location.origin).origin)
                headers.Authorization = `Bearer ${localStorage.getItem('vita.token') || ''}`;
            fetch(value, { headers, signal: controller.signal }).then(r => {
                if (!r.ok)
                    throw Error();
                return r.blob();
            }).then(blob => {
                objectURL = URL.createObjectURL(blob);
                if (active)
                    setURL(objectURL);
                else
                    URL.revokeObjectURL(objectURL);
            }).catch(() => { });
        }
        else
            setURL(value);
        return () => {
            active = false;
            controller.abort();
            if (objectURL)
                URL.revokeObjectURL(objectURL);
        };
    }, [src]);
    if (!url)
        return <div className={`media-placeholder ${className}`}><UserRound size={30}/></div>;
    if (kind === 'voice' || kind === 'audio')
        return <audio className={className} controls src={url}/>;
    if (kind === 'video')
        return <video className={className} controls playsInline src={url}/>;
    return <img className={className} src={url} alt={alt} loading="lazy" onError={() => setURL('')}/>;
}
function Modal({ title, close, children, t }: {
    title: string;
    close: () => void;
    children: ReactNode;
    t: T;
}) {
    const dialog = useRef<HTMLDialogElement>(null);
    useEffect(() => { dialog.current?.showModal(); return () => dialog.current?.close(); }, []);
    return <dialog ref={dialog} onCancel={close} onClick={e => {
            if (e.target === e.currentTarget)
                close();
        }}><div className="modal-head"><h2>{title}</h2><button className="icon-button" onClick={close} aria-label={t('close')}><X size={20}/></button></div>{children}</dialog>;
}
export default function VitaApp() {
    const [locale, setLocale] = useState<Locale>('zh-CN');
    const t: T = useCallback((key: MessageKey) => messages[locale][key], [locale]);
    const [section, setSection] = useState<Section>('world');
    const [authenticated, setAuthenticated] = useState(false);
    const [ready, setReady] = useState(false);
    const [auth, setAuth] = useState(false);
    const [create, setCreate] = useState(false);
    const [mobile, setMobile] = useState(false);
    const [collapsed, setCollapsed] = useState(false);
    const [dark, setDark] = useState(false);
    const [selected, setSelected] = useState('');
    const [revision, setRevision] = useState(0);
    const [notice, setNotice] = useState('');
    const [query, setQuery] = useState('');
    const companions = useResource(authenticated ? '/v1/companions/' : null, revision);
    const me = useResource(authenticated ? '/v1/me' : null, revision);
    const credits = useResource(authenticated ? '/v1/me/credits' : null, revision);
    const people = items(companions.data).filter(c => c.creation_source !== 'ai_pet');
    const current = people.find(c => c.id === selected) || people[0];
    useEffect(() => {
        setAuthenticated(session.exists());
        setReady(true);
        const saved = localStorage.getItem('vita.locale');
        if (saved === 'en' || saved === 'zh-CN')
            setLocale(saved);
        const savedTheme = localStorage.getItem('vita.theme');
        setDark(savedTheme ? savedTheme === 'dark' : window.matchMedia('(prefers-color-scheme: dark)').matches);
        const expired = () => { setAuthenticated(false); setSelected(''); setAuth(true); };
        const hash = () => {
            const value = window.location.hash.slice(1);
            if (['world', 'chat', 'journey', 'explore', 'stories', 'pets', 'account'].includes(value))
                setSection(value as Section);
        };
        hash();
        window.addEventListener('hashchange', hash);
        window.addEventListener('vita:expired', expired);
        return () => { window.removeEventListener('hashchange', hash); window.removeEventListener('vita:expired', expired); };
    }, []);
    useEffect(() => {
        document.documentElement.dataset.theme = dark ? 'dark' : 'light';
        if (ready)
            localStorage.setItem('vita.theme', dark ? 'dark' : 'light');
    }, [dark, ready]);
    useEffect(() => { document.documentElement.lang = locale; localStorage.setItem('vita.locale', locale); }, [locale]);
    useEffect(() => {
        if (!notice)
            return;
        const timer = setTimeout(() => setNotice(''), 5500);
        return () => clearTimeout(timer);
    }, [notice]);
    const navigate = (next: Section) => { setSection(next); setMobile(false); setQuery(''); window.location.hash = next; };
    const refresh = () => setRevision(n => n + 1);
    const openChat = (id: string) => { setSelected(id); navigate('chat'); };
    const requireAuth = (action: () => void) => {
        if (!authenticated)
            setAuth(true);
        else
            action();
    };
    const notify = (e: unknown) => setNotice(e instanceof Error ? e.message : t('failed'));
    const logout = async () => {
        try {
            await api('/v1/auth/logout', { method: 'POST' });
        }
        catch (e) {
            notify(e);
            return;
        }
        session.clear();
        sessionStorage.removeItem('vita.paypal-attempt');
        setAuthenticated(false);
        setSelected('');
        refresh();
        navigate('world');
    };
    return <div className={`app-shell ${collapsed ? 'sidebar-collapsed' : ''}`}>
    <a className="skip-link" href="#main">{t('enter')}</a>
    {mobile && <button className="nav-scrim" onClick={() => setMobile(false)} aria-label={t('collapse')}/>}
    <aside className={`sidebar ${mobile ? 'is-open' : ''}`}>
      <div className="brand-row"><a href="#world" className="wordmark" onClick={() => navigate('world')}>Vita</a><button className="icon-button desktop-collapse" onClick={() => setCollapsed(true)} aria-label={t('collapse')}><PanelLeft size={18}/></button><button className="icon-button sidebar-close" onClick={() => setMobile(false)} aria-label={t('collapse')}><X size={19}/></button></div>
      <button className="new-companion" onClick={() => requireAuth(() => setCreate(true))}><Plus size={19}/>{t('newCompanion')}</button>
      <nav aria-label="Vita">{navigation.map(({ id, Icon }) => <a href={`#${id}`} className={`nav-item ${section === id ? 'active' : ''}`} aria-current={section === id ? 'page' : undefined} key={id} onClick={() => navigate(id)}><Icon size={20}/>{t(id)}{section === id && <span className="active-dot"/>}</a>)}</nav>
      <div className="sidebar-label">{t('companions')}<button className="icon-button" aria-label={t('newCompanion')} onClick={() => requireAuth(() => setCreate(true))}><Plus size={15}/></button></div>
      <div className="sidebar-people">{people.map(person => <button key={person.id} className={`person-link ${section === 'chat' && current?.id === person.id ? 'selected' : ''}`} onClick={() => openChat(person.id)}><Media src={person.portrait_url} alt={person.name} className="avatar"/><span>{person.name}<small>{person.last_message || person.occupation}</small></span>{person.unread_count > 0 && <i className="unread">{person.unread_count}</i>}</button>)}{!people.length && <p className="sidebar-hint">{authenticated ? t('noCompanion') : t('loginRequired')}</p>}</div>
      <div className="sidebar-bottom"><button className="upgrade" onClick={() => requireAuth(() => navigate('account'))}><Sparkles size={19}/><span>{t('subscription')}<small>{t('membershipHint')}</small></span><ArrowUp size={15}/></button><button className={`profile-link ${section === 'account' ? 'selected' : ''}`} onClick={() => requireAuth(() => navigate('account'))}>{authenticated ? (me.data?.avatar_url ? <Media className="avatar" src={me.data.avatar_url} alt={me.data.nickname || ''}/> : <span className="initial">{(me.data?.nickname || me.data?.email || 'V').slice(0, 1).toUpperCase()}</span>) : <span className="initial guest-initial"><UserRound size={17}/></span>}<span>{me.data?.nickname || (authenticated ? me.data?.email : t('login'))}<small>{authenticated ? `${credits.data?.balance ?? '—'} ${t('credits')}` : 'Vita'}</small></span><Settings2 size={17}/></button></div>
    </aside>
    <div className="workspace"><header className="topbar"><div className="header-title"><button className={`icon-button mobile-menu ${collapsed ? 'show-expand' : ''}`} aria-label={t('menu')} onClick={() => { if (window.matchMedia('(max-width: 760px)').matches)
        setMobile(true); setCollapsed(false); }}><Menu size={21}/></button><span>{section === 'world' || section === 'chat' ? '' : t(section)}</span></div>{(section === 'world' || section === 'chat') && <div className="workspace-switch"><a href="#world" className={section === 'world' ? 'selected' : ''} onClick={() => navigate('world')}>{t('world')}</a><a href="#chat" className={section === 'chat' ? 'selected' : ''} onClick={() => navigate('chat')}>{t('chat')}</a></div>}<div className="header-actions"><button className="icon-button" onClick={() => setDark(!dark)} aria-label={t(dark ? 'light' : 'dark')}>{dark ? <Sun size={18}/> : <Moon size={18}/>}</button><select className="language-select" aria-label={t('language')} value={locale} onChange={e => setLocale(e.target.value as Locale)}><option value="zh-CN">简体中文</option><option value="en">English</option></select>{!authenticated && <button className="button small primary" onClick={() => setAuth(true)}>{t('login')}<ArrowRight size={14}/></button>}</div></header>
      <main id="main" className={`main-content ${section === 'chat' ? 'chat-main' : section === 'world' && !authenticated ? 'start-main' : ''}`}>
        {section === 'world' && (!authenticated ? <GuestHome t={t} login={() => setAuth(true)} navigate={navigate}/> : <><Heading title={t('world')} body={t('worldIntro')} eyebrow=""/><Status resource={companions} t={t}>{!people.length ? <Empty t={t}><button className="button primary" onClick={() => setCreate(true)}>{t('newCompanion')}</button></Empty> : <><div className="section-toolbar"><span>{t('companions')} <small>{people.length}</small></span><select aria-label={t('chooseCompanion')} value={current?.id || ''} onChange={e => setSelected(e.target.value)}>{people.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></div><World companion={current} t={t} revision={revision} onChat={openChat} notify={notify}/></>}</Status></>)}
        {section === 'chat' && (!authenticated ? <Guest t={t} login={() => setAuth(true)}/> : <Status resource={companions} t={t}>{current ? <Chat key={current.id} companion={current} t={t} notify={notify}/> : <Empty t={t}><button className="button primary" onClick={() => setCreate(true)}>{t('newCompanion')}</button></Empty>}</Status>)}
        {section === 'journey' && <><Heading title={t('journey')} body={t('journeyIntro')} eyebrow=""/><Journey authenticated={authenticated} people={people} t={t} login={() => setAuth(true)} query={query} setQuery={setQuery} notify={notify}/></>}
        {section === 'explore' && <div className="explore-content"><Heading title={t('explore')} body={t('exploreIntro')} eyebrow=""/><div className="explore-list"><button className="explore-row" onClick={() => navigate('stories')}><span className="explore-thumbnail story-thumbnail"><BookOpen size={28} strokeWidth={1.3}/></span><span className="explore-row-copy"><strong>{t('stories')}</strong><span>{t('storiesIntro')}</span></span><ArrowRight size={18}/></button><button className="explore-row" onClick={() => navigate('pets')}><span className="explore-thumbnail"><img src="/assets/ai_pets/cat_ragdoll.png" alt=""/></span><span className="explore-row-copy"><strong>{t('pets')}</strong><span>{t('petsIntro')}</span></span><ArrowRight size={18}/></button></div><ExplorePosts authenticated={authenticated} t={t}/></div>}
        {section === 'stories' && <><Heading title={t('stories')} body={t('storiesIntro')} eyebrow=""/>{authenticated ? <Stories t={t} people={people} notify={notify} refresh={refresh}/> : <Guest t={t} login={() => setAuth(true)}/>}</>}
        {section === 'pets' && <><Heading title={t('pets')} body={t('petsIntro')} eyebrow=""/>{authenticated ? <Pets t={t} notify={notify} refresh={refresh}/> : <Guest t={t} login={() => setAuth(true)}/>}</>}
        {section === 'account' && <><Heading title={t('account')} body={me.data?.email || ''} eyebrow=""/>{authenticated ? <Account t={t} me={me.data} revision={revision} refresh={refresh} notify={notify} logout={logout}/> : <Guest t={t} login={() => setAuth(true)}/>}</>}
      </main>
    </div>
    {notice && <div className="toast" role="status">{notice}<button className="icon-button" aria-label={t('close')} onClick={() => setNotice('')}><X size={16}/></button></div>}
    {auth && <Auth t={t} locale={locale} close={() => setAuth(false)} done={() => { setAuthenticated(true); setAuth(false); refresh(); if (sessionStorage.getItem('vita.message-draft'))
        navigate('chat'); }} notify={notify}/>}
    {create && <CreateCompanion t={t} close={() => setCreate(false)} done={id => { setCreate(false); refresh(); openChat(id); }} notify={notify}/>}
  </div>;
}
function Heading({ title, body, eyebrow }: {
    title: string;
    body: string;
    eyebrow: string;
}) { return <div className="page-heading"><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p>{body}</p></div>; }
function Guest({ t, login }: {
    t: T;
    login: () => void;
}) { return <div className="state guest-state"><h2>{t('loginTitle')}</h2><p>{t('loginRequired')}</p><button className="button primary" onClick={login}>{t('login')}<ArrowRight size={16}/></button></div>; }
function Auth({t,locale,close,done,notify}:{t:T;locale:Locale;close:()=>void;done:()=>void;notify:(e:unknown)=>void}) {
    const [mode,setMode]=useState<'login'|'register'|'verify'|'googleConsent'>('login');
    const [busy,setBusy]=useState(false);
    const [email,setEmail]=useState('');
    const [inviteCode,setInviteCode]=useState('');
    const [accepted,setAccepted]=useState(false);
    const busyRef=useRef(false);
    const active=useRef(true);
    const request=useRef<AbortController|null>(null);
    const pendingGoogle=useRef<string|null>(null);
    const legal=useResource('/v1/app-content?platform=app');
    const docs=legal.data?.legal_documents;
    const clientId=legal.data?.auth?.google_client_id || process.env.NEXT_PUBLIC_VITA_GOOGLE_CLIENT_ID || '';
    useEffect(()=>{active.current=true;return()=>{active.current=false;request.current?.abort();pendingGoogle.current=null}},[]);
    function startRequest(){
        if(busyRef.current)return null;
        busyRef.current=true;setBusy(true);
        request.current=new AbortController();return request.current;
    }
    function finishRequest(){if(active.current){busyRef.current=false;setBusy(false)}}
    function saveLogin(data:Entity){session.write(data);sessionStorage.removeItem('vita.paypal-attempt');pendingGoogle.current=null;done()}
    async function googleLogin(credential:string,consent?:GoogleConsent){
        const controller=startRequest();if(!controller)return;
        try{
            const data=await exchangeGoogleCredential(credential,consent,controller.signal);
            if(active.current)saveLogin(data);
        }catch(error){
            if(!active.current||controller.signal.aborted)return;
            if(error instanceof ApiError && ['legal_consent_required','legal_version_changed','legal_documents_unavailable'].includes(error.code||'')){
                pendingGoogle.current=credential;setAccepted(false);setMode('googleConsent');legal.reload();
            }else notify(error instanceof ApiError?error:new Error(t('googleFailed')));
        }finally{finishRequest()}
    }
    async function submit(event:FormEvent<HTMLFormElement>){
        event.preventDefault();
        if(mode==='googleConsent'){
            if(!accepted||!docs?.privacy?.version||!docs?.terms?.version||!pendingGoogle.current)return;
            await googleLogin(pendingGoogle.current,{privacyVersion:docs.privacy.version,termsVersion:docs.terms.version,inviteCode});return;
        }
        const form=new FormData(event.currentTarget);
        const controller=startRequest();if(!controller)return;
        try{
            if(mode==='register'){
                await api('/v1/auth/app/register',{method:'POST',signal:controller.signal,body:{email,password:form.get('password'),accepted_legal:accepted,privacy_policy_version:docs?.privacy?.version,terms_version:docs?.terms?.version,invite_code:inviteCode}});
                if(active.current)setMode('verify');
            }else{
                const data=await api(mode==='verify'?'/v1/auth/app/register/verify':'/v1/auth/app/login',{method:'POST',signal:controller.signal,body:{email,...(mode==='verify'?{code:form.get('code')}:{password:form.get('password')})}});
                if(active.current)saveLogin(data);
            }
        }catch(error){if(active.current&&!controller.signal.aborted)notify(error)}finally{finishRequest()}
    }
    const needsConsent=mode==='register'||mode==='googleConsent';
    return <Modal title={t(mode==='login'?'loginTitle':mode==='googleConsent'?'googleConsentTitle':'registerTitle')} close={close} t={t}>
        <p className="muted">{t(mode==='googleConsent'?'googleConsentBody':'loginBody')}</p>
        {(mode==='login'||mode==='register')&&<><GoogleSignIn clientId={clientId} locale={locale} disabled={busy} loadingConfig={legal.loading} t={t} onCredential={credential=>{void googleLogin(credential)}} reloadConfig={legal.reload}/><div className="auth-divider"><span>{t('emailAlternative')}</span></div></>}
        <form className="form auth-form" onSubmit={submit}>
            {mode!=='googleConsent'&&<label>{t('email')}<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="email" readOnly={mode==='verify'} disabled={busy}/></label>}
            {mode==='verify'?<label>{t('code')}<input name="code" required pattern="[0-9]{6}" inputMode="numeric" autoComplete="one-time-code" maxLength={6} disabled={busy}/></label>:mode!=='googleConsent'&&<label>{t('password')}<input type="password" name="password" required minLength={mode==='register'?6:1} maxLength={72} autoComplete={mode==='register'?'new-password':'current-password'} disabled={busy}/></label>}
            {needsConsent&&<><label>{t('invitationCode')}<input value={inviteCode} onChange={e=>setInviteCode(e.target.value)} disabled={busy}/></label><Status resource={legal} t={t}>{docs?.privacy&&docs?.terms?<><details><summary>{t('privacy')}</summary><div className="legal-copy">{docs.privacy.content}</div></details><details><summary>{t('terms')}</summary><div className="legal-copy">{docs.terms.content}</div></details><label className="checkbox"><input type="checkbox" checked={accepted} onChange={e=>setAccepted(e.target.checked)} required disabled={busy}/>{t('consent')} {t('privacy')} / {t('terms')}</label></>:<p className="muted">{t('noLegal')}</p>}</Status></>}
            <button className="button primary full" disabled={busy||(needsConsent&&(!accepted||!docs?.privacy?.version||!docs?.terms?.version))}>{busy?t('loading'):t(mode==='login'?'login':mode==='verify'?'verify':mode==='googleConsent'?'googleComplete':'sendCode')}<ArrowRight size={17}/></button>
            <button type="button" className="text-button" disabled={busy} onClick={()=>{pendingGoogle.current=null;setMode(mode==='login'?'register':'login');setAccepted(false)}}>{t(mode==='login'?'register':'login')}</button>
        </form>
    </Modal>;
}
function formRole(f: FormData) { return String(f.get('gender') || 'custom'); }
function CreateCompanion({ t, close, done, notify }: {
    t: T;
    close: () => void;
    done: (id: string) => void;
    notify: (e: unknown) => void;
}) {
    const options = useResource('/v1/companion-options');
    const [portrait, setPortrait] = useState('');
    const [busy, setBusy] = useState(false);
    const [media, setMedia] = useState('');
    const [draftMode, setDraftMode] = useState(false);
    const portraits = items(options.data, 'portraits').filter(p => p.gender !== 'pet');
    async function submit(e: FormEvent<HTMLFormElement>) {
        e.preventDefault();
        setBusy(true);
        const f = new FormData(e.currentTarget);
        try {
            const data = await api('/v1/companions/', { method: 'POST', body: { name: f.get('name'), persona: f.get('persona'), city: f.get('city'), occupation: f.get('occupation'), gender: formRole(f), relationship_stage: f.get('relationship_stage') || 'stranger', creation_source: 'tags_portrait', ...(media ? { avatar_media_id: media } : { portrait_id: portrait }) } });
            done(data.id);
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    if (draftMode)
        return <DraftCompanion t={t} close={close} back={() => setDraftMode(false)} done={done} notify={notify}/>;
    return <Modal title={t('newCompanion')} close={close} t={t}><button className="text-button" onClick={() => setDraftMode(true)}><Sparkles size={16}/>{t('generateCompanion')}</button><p className="muted">{t('createIntro')}</p><form className="form" onSubmit={submit}><label>{t('name')}<input name="name" required maxLength={100}/></label><label>{t('persona')}<textarea name="persona" rows={4} required maxLength={4000}/></label><div className="form-row"><label>{t('city')}<input name="city"/></label><label>{t('occupation')}<input name="occupation"/></label></div><label>{t('relationship')}<select name="gender">{items(options.data, 'relationships').map(r => <option value={r.key} key={r.key}>{productText('relation.' + r.key, t)}</option>)}</select></label><label>{t('portrait')}</label><Status resource={options} t={t}><div className="portrait-picker">{portraits.map(p => <button type="button" className={portrait === p.id && !media ? 'chosen' : ''} key={p.id} onClick={() => { setPortrait(p.id); setMedia(''); }} aria-label={p.name || t('selectPortrait')}><Media src={p.image_url} alt={p.name}/></button>)}</div></Status><label className="upload-label">{media ? <Check size={17}/> : <Plus size={17}/>} {t('upload')}<input type="file" accept="image/*" disabled={busy} onChange={async (e) => {
            const file = e.target.files?.[0];
            if (!file)
                return;
            setBusy(true);
            try {
                const f = new FormData();
                f.set('file', file);
                f.set('kind', 'image');
                const d = await api('/v1/companions/image', { method: 'POST', body: f });
                setMedia(d.id);
            }
            catch (e) {
                notify(e);
            }
            finally {
                setBusy(false);
            }
        }}/></label><button className="button primary" disabled={busy || (!portrait && !media)}>{busy ? t('loading') : t('newCompanion')}<ArrowRight size={16}/></button></form></Modal>;
}
function World({ companion, t, revision, onChat, notify }: {
    companion: Entity;
    t: T;
    revision: number;
    onChat: (id: string) => void;
    notify: (e: unknown) => void;
}) {
    const resource = useResource(`/v1/companions/${companion.id}/world/scene`, revision);
    const [busy, setBusy] = useState(false);
    const [reaction, setReaction] = useState('');
    const [momentID, setMomentID] = useState('');
    const scene = resource.data;
    async function visit(choice: string) {
        setBusy(true);
        try {
            const d = await api(`/v1/companions/${companion.id}/world/visit`, { method: 'POST', body: { choice } });
            setReaction(d.reaction || d.message || d.today_visit?.reaction || '');
            resource.reload();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    return <Status resource={resource} t={t}>{scene && <><div className="world-card"><div className="world-portrait"><Media src={companion.portrait_url} alt={companion.name}/><span className="world-tag"><span className="live-dot"/>{companion.city || productText(scene.place?.title || 'Vita', t)}</span></div><div className="world-story"><div className="eyebrow">{t('today')} · {scene.local_date}</div><h2>{companion.name}<span>{productText(scene.place?.title || '', t)}</span></h2><p className="world-description">{scene.event?.description || scene.place?.description || companion.persona}</p>{scene.event?.title && <div className="activity"><span className="live-dot"/>{productText(scene.event.title, t)}</div>}<div className="world-actions">{scene.visited_today ? <span className="visited"><Check size={16}/>{t('visited')}</span> : <><button className="button primary" disabled={busy} onClick={() => visit('stay')}><Heart size={17}/>{t('visit')}</button><button className="button" disabled={busy} onClick={() => visit('ask')}>{t('ask')}</button></>}<button className="text-button" onClick={() => onChat(companion.id)}>{t('continueChat')}<ArrowRight size={16}/></button></div></div></div>{(reaction || scene.today_visit?.reaction) && <div className="reaction"><Sparkles size={20}/><p>{reaction || scene.today_visit.reaction}</p><button className="text-button" onClick={() => onChat(companion.id)}>{t('continueChat')}<ArrowRight size={16}/></button></div>}{scene.appointment && <button className="appointment-banner" onClick={() => setMomentID(scene.appointment.id)}><BookOpen size={21}/><span>{productText(scene.appointment.title_key, t)}<small>{new Date(scene.appointment.starts_at).toLocaleString()}</small></span><ArrowRight size={18}/></button>}{momentID && <Moment companion={companion} eventID={momentID} t={t} notify={notify} close={() => setMomentID('')}/>}<div className="world-bottom"><article className="info-card"><span className="eyebrow">{t('next')}</span><h3>{scene.next_event?.title || companion.occupation || companion.name}</h3><p>{scene.next_event?.description || companion.interests || t('worldIntro')}</p></article><article className="info-card"><span className="eyebrow">{t('memories')}</span>{items(scene, 'memories').length ? items(scene, 'memories').slice(0, 2).map(m => <p key={m.id}>{m.content}</p>) : <p>{t('journeyIntro')}</p>}</article></div></>}</Status>;
}
function Chat({ companion, t, notify, eventID }: {
    companion: Entity;
    t: T;
    notify: (e: unknown) => void;
    eventID?: string;
}) {
    const [profile, setProfile] = useState(false);
    const [experiences, setExperiences] = useState(false);
    const [momentID, setMomentID] = useState('');
    const messageQuery = eventID ? `channel=date&event_id=${encodeURIComponent(eventID)}` : 'channel=chat';
    const [conversation, setConversation] = useState<Entity | null>(null);
    const [messages, setMessages] = useState<Entity[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [busy, setBusy] = useState(false);
    const [pending, setPending] = useState(false);
    const [replyFailed, setReplyFailed] = useState(false);
    const [text, setText] = useState(() => typeof window !== 'undefined' && !eventID ? sessionStorage.getItem('vita.message-draft') || '' : '');
    const [version, setVersion] = useState(0);
    const end = useRef<HTMLDivElement>(null);
    useEffect(() => {
        let active = true;
        setLoading(true);
        api('/v1/conversations/', { method: 'POST', body: { companion_id: companion.id, ...(eventID ? { date_event_id: eventID } : {}) } }).then(async (c) => {
            const data = await api(`/v1/conversations/${c.conversation_id}/messages?${messageQuery}`);
            if (active) {
                setConversation(c);
                setMessages(items(data));
                setError('');
            }
        }).catch(e => {
            if (active)
                setError(e.message);
        }).finally(() => {
            if (active)
                setLoading(false);
        });
        return () => { active = false; };
    }, [companion.id, version]);
    useEffect(() => {
        if (!conversation)
            return;
        let active = true;
        let timer: ReturnType<typeof setTimeout>;
        const poll = async () => {
            try {
                const [data, status] = await Promise.all([api(`/v1/conversations/${conversation.conversation_id}/messages?${messageQuery}`), api(`/v1/conversations/${conversation.conversation_id}/reply-status?${messageQuery}`)]);
                if (active) {
                    setMessages(items(data));
                    setPending(['pending', 'processing', 'queued'].includes(status.status));
                    setReplyFailed(status.status === 'failed');
                }
            }
            catch (e) {
                if (active)
                    setError(e instanceof Error ? e.message : t('failed'));
            }
            finally {
                if (active)
                    timer = setTimeout(poll, 4000);
            }
        };
        timer = setTimeout(poll, 1000);
        return () => { active = false; clearTimeout(timer); };
    }, [conversation, t]);
    useEffect(() => { end.current?.scrollIntoView({ behavior: 'instant', block: 'end' }); }, [messages.length, pending]);
    async function send(e: FormEvent) {
        e.preventDefault();
        if (!text.trim() || !conversation || busy)
            return;
        setBusy(true);
        try {
            const d = await api(`/v1/conversations/${conversation.conversation_id}/messages`, { method: 'POST', body: { content: text, message_type: 'text', ...(eventID ? { life_event_id: eventID } : {}) } });
            setText('');
            sessionStorage.removeItem('vita.message-draft');
            setPending(['pending', 'processing', 'queued'].includes(d.reply_status));
            setReplyFailed(!!d.agent_error);
            setMessages(items(await api(`/v1/conversations/${conversation.conversation_id}/messages?${messageQuery}`)));
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    return <div className="conversation"><div className="conversation-head"><Media src={companion.portrait_url} alt={companion.name} className="avatar"/><div><h2>{companion.name}</h2><small>{conversation?.companion_status?.title || companion.occupation}</small></div><span className="conversation-meta">{companion.city}</span>{!eventID && <><button className="icon-button" aria-label={t('experiences')} onClick={() => setExperiences(true)}><Sparkles size={19}/></button><button className="icon-button" aria-label={t('details')} onClick={() => setProfile(true)}><MoreHorizontal size={20}/></button></>}</div><div className="messages">{loading ? <div className="state">{t('loading')}</div> : error ? <div className="inline-error" role="alert">{error}<button className="text-button" onClick={() => setVersion(v => v + 1)}>{t('retry')}</button></div> : null}{!loading && !error && !messages.length && <div className="conversation-empty"><h1>{t('chatEmpty')}</h1><p>{t('chatIntro')}</p></div>}{messages.map(m => <article className={`message ${m.sender_type === 'user' ? 'user-message' : 'companion-message'}`} key={m.id}><span className="message-author">{m.sender_type === 'user' ? t('account') : companion.name}</span>{m.content && <p>{m.content}</p>}{m.media_url && <Media src={m.media_url} kind={m.message_type} alt={t('image')} className="message-media"/>}<time>{new Date(m.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</time></article>)}{pending && <div className="replying"><span className="spinner"/>{t('replying')}</div>}{replyFailed && <div className="inline-error">{t('replyFailed')}<button className="text-button" disabled={busy} onClick={async () => {
                if (!conversation)
                    return;
                setBusy(true);
                try {
                    await api(`/v1/conversations/${conversation.conversation_id}/reply-status/retry`, { method: 'POST' });
                    setReplyFailed(false);
                    setPending(true);
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}>{t('retry')}</button></div>}<div ref={end}/></div><div className="composer-wrap">{conversation?.can_send === false ? <p className="inline-error">{conversation.access_code || t('subscription')}</p> : <form className="composer" onSubmit={send}><textarea aria-label={t('message')} value={text} onChange={e => setText(e.target.value)} placeholder={t('message')} rows={2} onKeyDown={e => {
                if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                    e.preventDefault();
                    e.currentTarget.form?.requestSubmit();
                }
            }}/><div className="composer-bottom"><label className="icon-button attachment" title={t('attachment')}><Plus size={21}/><span className="sr-only">{t('attachment')}</span><input type="file" accept="audio/*" disabled={busy || !conversation} onChange={async (e) => {
                const file = e.target.files?.[0];
                if (!file || !conversation)
                    return;
                setBusy(true);
                try {
                    const f = new FormData();
                    f.set('file', file);
                    f.set('kind', 'audio');
                    const uploaded = await api('/v1/media/upload', { method: 'POST', body: f });
                    await api(`/v1/conversations/${conversation.conversation_id}/messages`, { method: 'POST', body: { message_type: 'voice', media_id: uploaded.id, ...(eventID ? { life_event_id: eventID } : {}) } });
                    setPending(true);
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                    e.target.value = '';
                }
            }}/></label><span>Vita · {companion.name}</span><button className="send-button" disabled={!text.trim() || busy || !conversation} aria-label={t('send')}><ArrowUp size={20}/></button></div></form>}<p className="composer-note">{t('chatIntro')}</p></div>{profile && <CompanionProfile companion={companion} t={t} notify={notify} close={() => setProfile(false)}/>}{experiences && <Experiences companion={companion} t={t} notify={notify} close={() => setExperiences(false)} onMoment={id => { setExperiences(false); setMomentID(id); }}/>}{momentID && <Moment companion={companion} eventID={momentID} t={t} notify={notify} close={() => setMomentID('')}/>}</div>;
}
function Journey({ authenticated, people, t, login, query, setQuery, notify }: {
    authenticated: boolean;
    people: Entity[];
    t: T;
    login: () => void;
    query: string;
    setQuery: (s: string) => void;
    notify: (e: unknown) => void;
}) {
    const [selected, setSelected] = useState('');
    const [offset, setOffset] = useState(0);
    const [all, setAll] = useState<Entity[]>([]);
    const [detail, setDetail] = useState<Entity | null>(null);
    const [busy, setBusy] = useState(false);
    const [search, setSearch] = useState('');
    useEffect(() => { const timer = setTimeout(() => { setSearch(query); setOffset(0); setAll([]); }, 300); return () => clearTimeout(timer); }, [query]);
    const resource = useResource(authenticated ? `/v1/journey?limit=30&offset=${offset}&companion_id=${encodeURIComponent(selected)}&q=${encodeURIComponent(search)}` : null);
    useEffect(() => {
        if (resource.data)
            setAll(old => offset === 0 ? items(resource.data) : [...old, ...items(resource.data).filter(m => !old.some(o => o.id === m.id))]);
    }, [resource.data, offset]);
    if (!authenticated)
        return <Guest t={t} login={login}/>;
    async function modify(method: string, body?: Entity) {
        if (!detail)
            return;
        setBusy(true);
        try {
            await api(`/v1/companions/${detail.companion?.id || detail.companion_id}/memories/${detail.id}`, { method, body });
            setDetail(null);
            setOffset(0);
            resource.reload();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    return <><div className="section-toolbar"><label className="search-field"><Search size={17}/><input aria-label={t('search')} placeholder={t('search')} value={query} onChange={e => setQuery(e.target.value)}/></label><select aria-label={t('chooseCompanion')} value={selected} onChange={e => { setSelected(e.target.value); setOffset(0); setAll([]); }}><option value="">{t('all')}</option>{people.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></div><Status resource={resource} t={t}>{all.length ? <div className="memory-grid">{all.map(m => <button className="memory-card" key={m.id} onClick={() => setDetail(m)}><span className="memory-date">{new Date(m.event_time).toLocaleDateString()}</span><h3>{m.title || m.companion?.name}</h3><p>{m.content}</p><span className="memory-author"><Heart size={14}/>{m.companion?.name}<ArrowRight size={15}/></span></button>)}</div> : <Empty t={t}/>}</Status>{items(resource.data).length === 30 && <button className="button load-more" onClick={() => setOffset(v => v + 30)}>{t('more')}<ArrowDown size={15}/></button>}{detail && <Modal title={detail.title || detail.companion?.name || t('memories')} close={() => setDetail(null)} t={t}>{detail.readonly ? <><p className="prose">{detail.content}</p><small className="muted">{t('readonly')}</small></> : <form className="form" onSubmit={e => { e.preventDefault(); void modify('PUT', { content: new FormData(e.currentTarget).get('content') }); }}><textarea name="content" defaultValue={detail.content} required maxLength={500} rows={8}/><MemoryFavorite companionID={detail.companion?.id || detail.companion_id} memoryID={detail.id} t={t} notify={notify}/><div className="form-row"><button className="button primary" disabled={busy}>{t('save')}</button><button type="button" className="button" disabled={busy} onClick={() => {
                    if (window.confirm(t('confirmDelete')))
                        void modify('DELETE');
                }}>{t('delete')}</button></div></form>}</Modal>}</>;
}
function ExplorePosts({ authenticated, t }: {
    authenticated: boolean;
    t: T;
}) {
    const posts = useResource(authenticated ? '/v1/explore/posts' : null);
    const [detail, setDetail] = useState<Entity | null>(null);
    return <><Status resource={posts} t={t}>{items(posts.data, 'posts').length > 0 && <div className="posts-grid">{items(posts.data, 'posts').map(p => <button className="info-card post-card" key={p.id} onClick={() => setDetail(p)}>{p.image_url && <Media src={p.image_url} alt={p.title}/>}<h3>{p.title}</h3><p>{p.content || p.body}</p></button>)}</div>}</Status>{detail && <Modal title={detail.title || t('details')} close={() => setDetail(null)} t={t}><p className="prose">{detail.content || detail.body}</p></Modal>}</>;
}
function Stories({ t, people, notify, refresh }: {
    t: T;
    people: Entity[];
    notify: (e: unknown) => void;
    refresh: () => void;
}) {
    const catalog = useResource('/v1/stories/catalog');
    const stories = useResource('/v1/stories/');
    const [customBackground, setCustomBackground] = useState(false);
    const storyAttempt = useRef<{
        action: string;
        key: string;
    } | null>(null);
    const [selected, setSelected] = useState('');
    const [detail, setDetail] = useState<Entity | null>(null);
    const [busy, setBusy] = useState(false);
    async function start(background: string) {
        setBusy(true);
        if (!storyAttempt.current || storyAttempt.current.action !== background)
            storyAttempt.current = { action: background, key: crypto.randomUUID() };
        try {
            const d = await api('/v1/stories/', { method: 'POST', body: { background_id: background, ...(selected ? { companion_id: selected } : {}), idempotency_key: storyAttempt.current.key } });
            setDetail(d);
            storyAttempt.current = null;
            stories.reload();
            refresh();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    async function choose(choice: string) {
        if (!detail)
            return;
        setBusy(true);
        const action = detail.id + ':' + detail.current_chapter_no + ':' + choice;
        if (!storyAttempt.current || storyAttempt.current.action !== action)
            storyAttempt.current = { action, key: crypto.randomUUID() };
        try {
            setDetail(await api(`/v1/stories/${detail.id}/choices`, { method: 'POST', body: { choice_id: choice, idempotency_key: storyAttempt.current.key } }));
            storyAttempt.current = null;
            refresh();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    if (detail)
        return <><button className="text-button" onClick={() => setDetail(null)}><ArrowLeft size={17}/>{t('back')}</button><div className="story-reader"><h2>{detail.title}</h2>{items(detail, 'chapters').map((chapter, i, array) => <article className="chapter" key={chapter.id}><span className="eyebrow">{String(chapter.chapter_no).padStart(2, '0')}</span><h3>{chapter.title}</h3><p className="prose">{chapter.content}</p>{i === array.length - 1 && <div className="story-choices">{items(chapter, 'choices').map(c => <button className="button" key={c.id} disabled={busy || detail.can_continue === false} onClick={() => choose(c.id)}>{c.text}<ArrowRight size={16}/></button>)}</div>}</article>)}{items(detail, 'storyboards').map(b => <article key={b.id}><p>{b.summary || b.failure_reason || b.status}</p>{b.image_url && <Media src={b.image_url} alt={detail.title}/>}</article>)}<StoryBoardAction story={detail} t={t} notify={notify} changed={async () => setDetail(await api(`/v1/stories/${detail.id}`))}/><p className="muted">{t('storyCost')}</p></div></>;
    return <><Status resource={stories} t={t}>{items(stories.data).length > 0 && <><div className="section-toolbar"><h2>{t('read')}</h2></div><div className="memory-grid">{items(stories.data).map(s => <button className="memory-card" key={s.id} disabled={busy} onClick={async () => {
                    setBusy(true);
                    try {
                        setDetail(await api(`/v1/stories/${s.id}`));
                    }
                    catch (e) {
                        notify(e);
                    }
                    finally {
                        setBusy(false);
                    }
                }}><BookOpen size={22}/><h3>{s.title}</h3><p>{s.companion?.name}</p><span className="memory-author">{t('read')}<ArrowRight size={16}/></span></button>)}</div></>}</Status><div className="section-toolbar"><h2>{t('startStory')}</h2><button className="text-button" onClick={() => setCustomBackground(true)}><Plus size={15}/>{t('background')}</button><select value={selected} onChange={e => setSelected(e.target.value)} aria-label={t('chooseCompanion')}><option value="">{t('chooseCompanion')}</option>{people.map(p => <option value={p.id} key={p.id}>{p.name}</option>)}</select></div><Status resource={catalog} t={t}><div className="catalog-grid">{items(catalog.data, 'backgrounds').map(b => <article className="catalog-card" key={b.id}><Media src={b.cover_url} alt={b.title}/><div><span className="eyebrow">{b.genre}</span><h3>{b.title}</h3><p>{b.synopsis}</p><button className="button" disabled={busy} onClick={() => start(b.id)}>{t('startStory')}<ArrowRight size={15}/></button></div></article>)}</div>{!items(catalog.data, 'backgrounds').length && <Empty t={t}/>}</Status>{customBackground && <StoryBackground t={t} close={() => setCustomBackground(false)} done={() => { setCustomBackground(false); catalog.reload(); }} notify={notify}/>}</>;
}
function Pets({ t, notify, refresh }: {
    t: T;
    notify: (e: unknown) => void;
    refresh: () => void;
}) {
    const breeds = useResource('/v1/ai-pets/breeds');
    const [pet, setPet] = useState<Entity | null>(null);
    const state = useResource(pet ? `/v1/ai-pets/${pet.adopted_companion_id}/state` : null);
    const [adopting, setAdopting] = useState<Entity | null>(null);
    const [busy, setBusy] = useState(false);
    async function care(kind: string) {
        if (!pet)
            return;
        setBusy(true);
        try {
            await api(`/v1/ai-pets/${pet.adopted_companion_id}/${kind === 'feed' ? 'feed' : 'care'}`, { method: 'POST', body: { kind, idempotency_key: crypto.randomUUID() } });
            state.reload();
            refresh();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    if (pet)
        return <><button className="text-button" onClick={() => setPet(null)}><ArrowLeft size={16}/>{t('back')}</button><Status resource={state} t={t}>{state.data && <div className="pet-home"><div className="pet-stage"><Media src={state.data.avatar_url || pet.avatar_url} alt={pet.name}/><span className="pet-shadow"/></div><h2>{pet.adopted_companion_name || pet.name}</h2><span className="muted">{t('level')} {state.data.level}</span><div className="pet-stats">{(['hunger', 'hydration', 'happiness', 'energy', 'health'] as const).map(key => <label key={key}>{t(key)}<span>{state.data[key]} / 100</span><progress max={100} value={state.data[key]}/></label>)}</div><div className="pet-actions">{(['pet', 'drink', 'walk', 'rest', 'feed'] as const).map(k => <button className={`button ${k === 'feed' ? 'primary' : ''}`} disabled={busy} key={k} onClick={() => care(k)}>{t(k)}{k === 'feed' ? ` · ${state.data.feed_coin_cost} ${t('credits')}` : ''}</button>)}</div></div>}</Status></>;
    return <><Status resource={breeds} t={t}><div className="catalog-grid">{items(breeds.data).map(b => <article className="catalog-card pet-catalog" key={b.id}><Media src={b.avatar_url} alt={b.name}/><div><span className="eyebrow">{b.species}</span><h3>{b.name}</h3><p>{b.description}</p><button className="button" disabled={!b.adopted_companion_id && !b.can_adopt} onClick={() => b.adopted_companion_id ? setPet(b) : setAdopting(b)}>{t(b.adopted_companion_id ? 'enter' : 'adopt')}<ArrowRight size={16}/></button>{!b.adopted_companion_id && !b.can_adopt && <small>{t('subscription')}</small>}</div></article>)}</div>{!items(breeds.data).length && <Empty t={t}/>}</Status>{adopting && <Modal title={`${t('adopt')} · ${adopting.name}`} close={() => setAdopting(null)} t={t}><form className="form" onSubmit={async (e) => {
                e.preventDefault();
                const name = new FormData(e.currentTarget).get('name');
                setBusy(true);
                try {
                    const data = await api('/v1/ai-pets/adopt', { method: 'POST', body: { name, breed_id: adopting.id } });
                    setPet({ ...adopting, adopted_companion_id: data.companion_id, adopted_companion_name: data.name });
                    setAdopting(null);
                    breeds.reload();
                    refresh();
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}><label>{t('name')}<input name="name" required maxLength={40} defaultValue={adopting.name}/></label><button className="button primary" disabled={busy}>{t('adopt')}</button></form></Modal>}</>;
}
function Account({ t, me, revision, refresh, notify, logout }: {
    t: T;
    me: Entity | null;
    revision: number;
    refresh: () => void;
    notify: (e: unknown) => void;
    logout: () => void;
}) {
    const subscription = useResource('/v1/me/subscription', revision);
    const credits = useResource('/v1/me/credits', revision);
    const [busy, setBusy] = useState(false);
    async function submit(e: FormEvent<HTMLFormElement>, path: string, method = 'PUT') {
        e.preventDefault();
        const form = e.currentTarget;
        const data = Object.fromEntries(new FormData(form));
        setBusy(true);
        try {
            await api(path, { method, body: data });
            notify(new Error(t('saved')));
            refresh();
            if (path === '/v1/feedback')
                form.reset();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    return <div className="account-layout"><div><section className="account-panel"><h2>{t('profile')}</h2><form className="form" onSubmit={e => submit(e, '/v1/me/profile')}><label>{t('nickname')}<input name="nickname" defaultValue={me?.nickname || ''} maxLength={30}/></label><button className="button" disabled={busy}>{t('save')}</button></form></section><section className="account-panel"><h2>{t('security')}</h2><form className="form" onSubmit={e => submit(e, '/v1/me/password')}><label>{t('currentPassword')}<input name="current_password" type="password" autoComplete="current-password" required/></label><label>{t('newPassword')}<input name="new_password" type="password" minLength={6} maxLength={72} autoComplete="new-password" required/></label><button className="button" disabled={busy}>{t('save')}</button></form></section><section className="account-panel"><h2>{t('feedback')}</h2><form className="form" onSubmit={e => submit(e, '/v1/feedback', 'POST')}><textarea name="content" rows={4} placeholder={t('feedbackHint')} required maxLength={2000}/><button className="button" disabled={busy}>{t('send')}</button></form></section><Preferences t={t} notify={notify}/><button className="text-button logout" onClick={logout}><LogOut size={17}/>{t('logout')}</button></div><div><section className="membership-panel"><Sparkles size={25}/><h2>{t('subscription')}</h2><Status resource={subscription} t={t}><p>{t(subscription.data?.is_subscribed ? 'subscribed' : 'notSubscribed')}</p>{subscription.data?.subscription?.current_period_end && <small>{new Date(subscription.data.subscription.current_period_end).toLocaleDateString()}</small>}</Status>{subscription.data?.subscription?.provider === 'paypal' && subscription.data.subscription.will_renew && <button className="button" disabled={busy} onClick={async () => {
                if (!window.confirm(t('confirmCancel')))
                    return;
                setBusy(true);
                try {
                    await api(`/v1/paypal/subscriptions/${subscription.data.subscription.id}/cancel`, { method: 'POST' });
                    refresh();
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}>{t('cancelRenewal')}</button>}<Billing t={t} notify={notify} refresh={refresh}/></section><section className="account-panel"><span className="eyebrow">{t('credits')}</span><Status resource={credits} t={t}><div className="balance">{credits.data?.balance ?? '—'}<span>{t('credits')}</span></div><h3>{t('transactions')}</h3><div className="transactions">{items(credits.data, 'transactions').map(tx => <div className="transaction" key={tx.id}><span>{tx.description || tx.kind}<small>{new Date(tx.created_at).toLocaleDateString()}</small></span><strong>{tx.amount > 0 ? '+' : ''}{tx.amount}</strong></div>)}{!items(credits.data, 'transactions').length && <p className="muted">{t('empty')}</p>}</div></Status></section><section className="account-panel"><h2>{t('invitation')}</h2>{me?.invite_code && <div className="invite-code">{me.invite_code}</div>}<form className="form" onSubmit={e => submit(e, '/v1/me/invitation', 'POST')}><label>{t('invitationCode')}<input name="invite_code" required/></label><button className="button" disabled={busy}>{t('bind')}</button></form></section></div></div>;
}
function Billing({ t, notify, refresh }: {
    t: T;
    notify: (e: unknown) => void;
    refresh: () => void;
}) {
    const catalog = useResource('/v1/paypal/catalog');
    const [busy, setBusy] = useState(false);
    const [status, setStatus] = useState('');
    useEffect(() => {
        const checkout = new URLSearchParams(window.location.search).get('checkout');
        if (!checkout)
            return;
        let active = true;
        let timer: ReturnType<typeof setTimeout>;
        let attempts = 0;
        const confirm = async () => {
            setBusy(true);
            try {
                const d = await api(`/v1/paypal/checkouts/${encodeURIComponent(checkout)}/confirm`, { method: 'POST' });
                if (!active)
                    return;
                if (d.status === 'confirmed') {
                    setStatus(t('paymentConfirmed'));
                    refresh();
                    sessionStorage.removeItem('vita.paypal-attempt');
                    window.history.replaceState(null, '', window.location.pathname + '#account');
                    setBusy(false);
                }
                else {
                    setStatus(t('paymentPending'));
                    if (++attempts < 12)
                        timer = setTimeout(confirm, 3000);
                    else
                        setBusy(false);
                }
            }
            catch (e) {
                if (active) {
                    notify(e);
                    setBusy(false);
                }
            }
        };
        void confirm();
        return () => { active = false; clearTimeout(timer); };
    }, []);
    async function buy(product: Entity) {
        setBusy(true);
        try {
            const d = await api('/v1/paypal/checkouts', { method: 'POST', body: checkoutAttempt(product) });
            const url = new URL(d.url);
            if (url.protocol !== 'https:' || !['www.sandbox.paypal.com', 'www.paypal.com'].includes(url.hostname))
                throw Error(t('failed'));
            window.location.assign(url.href);
        }
        catch (e) {
            notify(e);
            setBusy(false);
        }
    }
    return <Status resource={catalog} t={t}>{status && <p role="status">{status}{!busy && status === t('paymentPending') && <button className="text-button" onClick={() => window.location.reload()}>{t('retry')}</button>}</p>}<div className="billing-products">{items(catalog.data).map(p => <div className="billing-product" key={`${p.kind}:${p.key}`}><div><strong>{p.name}</strong><p>{p.kind === 'coin' ? `${p.coins} ${t('credits')}` : t('subscription')}</p><small>USD {p.price_usd}{p.period ? ` / ${p.period}` : ''}</small></div><button className="button primary" disabled={busy || !catalog.data?.available} onClick={() => buy(p)}>PayPal<ArrowRight size={15}/></button></div>)}</div>{!catalog.data?.available && <p className="muted">{t('payPendingBody')}</p>}</Status>;
}
function CompanionProfile({ companion, t, close, notify }: {
    companion: Entity;
    t: T;
    close: () => void;
    notify: (e: unknown) => void;
}) {
    const resource = useResource(`/v1/companions/${companion.id}`);
    const [busy, setBusy] = useState(false);
    return <Modal title={companion.name} close={close} t={t}><Status resource={resource} t={t}>{resource.data && <form className="form" onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                const f = new FormData(e.currentTarget);
                try {
                    await api(`/v1/companions/${companion.id}`, { method: 'PUT', body: { ...resource.data, ...Object.fromEntries(f) } });
                    notify(new Error(t('saved')));
                    close();
                    window.location.reload();
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}><Media src={resource.data.portrait_url} alt={companion.name} className="profile-portrait"/>{(['name', 'persona', 'city', 'occupation'] as const).map(k => <label key={k}>{t(k)}{k === 'persona' ? <textarea name={k} defaultValue={resource.data[k]} rows={5}/> : <input name={k} defaultValue={resource.data[k]} required={k === 'name'}/>}</label>)}<button className="button primary" disabled={busy}>{t('save')}</button>{!resource.data.is_default && <button type="button" className="text-button" disabled={busy} onClick={async () => {
                    if (!window.confirm(t('confirmDelete')))
                        return;
                    setBusy(true);
                    try {
                        await api(`/v1/companions/${companion.id}`, { method: 'DELETE' });
                        window.location.reload();
                    }
                    catch (e) {
                        notify(e);
                        setBusy(false);
                    }
                }}>{t('delete')}</button>}</form>}</Status></Modal>;
}
function Experiences({ companion, t, close, notify, onMoment }: {
    companion: Entity;
    t: T;
    close: () => void;
    notify: (e: unknown) => void;
    onMoment: (id: string) => void;
}) {
    const catalog = useResource(`/v1/companions/${companion.id}/experiences`);
    const [product, setProduct] = useState<Entity | null>(null);
    const slots = useResource(product?.category === 'date' ? `/v1/companions/${companion.id}/experiences/${product.key}/slots` : null);
    const [busy, setBusy] = useState(false);
    const [result, setResult] = useState<Entity | null>(null);
    const attempt = useRef<{
        key: string;
        body: Entity;
    } | null>(null);
    async function buy(e: FormEvent<HTMLFormElement>) {
        e.preventDefault();
        if (!product)
            return;
        setBusy(true);
        const f = new FormData(e.currentTarget);
        if (!attempt.current)
            attempt.current = { key: product.key, body: { idempotency_key: crypto.randomUUID(), input: { quoted_coins: product.coins, custom_request: f.get('custom_request') || '', ...(f.get('scheduled_at') ? { scheduled_at: f.get('scheduled_at') } : {}) } } };
        try {
            const d = await api(`/v1/companions/${companion.id}/experiences/${attempt.current.key}`, { method: 'POST', body: attempt.current.body });
            setResult(d.result);
            attempt.current = null;
            catalog.reload();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    return <Modal title={t('experiences')} close={close} t={t}>{result ? <div className="experience-result">{(result.media_url || result.message?.media_url) && <Media src={result.media_url || result.message.media_url} kind={result.media_type || result.message?.message_type || result.type} alt={companion.name} className="result-media"/>}<p className="prose">{result.reaction || result.content || (typeof result.message === 'string' ? result.message : result.message?.content) || result.invitation || result.description}</p>{result.event_id && <button className="button primary" onClick={() => onMoment(result.event_id)}>{t('appointment')}<ArrowRight size={16}/></button>}<button className="text-button" onClick={() => { close(); }}>{t('continueChat')}<ArrowRight size={16}/></button></div> : product ? <form className="form" onSubmit={buy}><button className="text-button" type="button" disabled={busy || !!attempt.current} onClick={() => setProduct(null)}><ArrowLeft size={16}/>{t('back')}</button><h3>{productText(product.name_key, t)}</h3><p className="muted">{productText(product.description_key, t)}</p><label>{t('customRequest')}<textarea name="custom_request" rows={3} maxLength={500} disabled={!!attempt.current}/></label>{product.category === 'date' && <Status resource={slots} t={t}><label>{t('appointment')}<select name="scheduled_at" required disabled={!!attempt.current}><option value="">{t('appointment')}</option>{items(slots.data, 'slots').map(s => <option key={s.starts_at} value={s.starts_at}>{new Date(s.starts_at).toLocaleString()}</option>)}</select></label></Status>}<p>{product.coins} {t('credits')}</p><button className="button primary" disabled={busy}>{busy ? t('loading') : attempt.current ? t('retry') : t('confirmPurchase')}</button></form> : <Status resource={catalog} t={t}><p className="muted">{catalog.data?.balance ?? '—'} {t('credits')}</p><div className="experience-list">{items(catalog.data, 'products').filter(p => p.is_launched).map(p => <button className="experience-product" key={p.key} onClick={() => { setProduct(p); attempt.current = null; }}><span>{p.emoji}</span><span><strong>{productText(p.name_key, t)}</strong><small>{productText(p.description_key, t)}</small></span><span>{p.coins}<small>{t('credits')}</small></span></button>)}</div></Status>}</Modal>;
}
function Moment({ companion, eventID, t, notify, close }: {
    companion: Entity;
    eventID: string;
    t: T;
    notify: (e: unknown) => void;
    close: () => void;
}) {
    const path = `/v1/companions/${companion.id}/moments/${eventID}`;
    const resource = useResource(path);
    const [busy, setBusy] = useState(false);
    const [started, setStarted] = useState(false);
    const moment = resource.data;
    async function action(name: string, body?: Entity, method = 'POST') {
        setBusy(true);
        try {
            const d = await api(path + '/' + name, { method, body });
            if (name === 'start')
                setStarted(true);
            resource.reload();
            return d;
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    return <Modal title={moment ? productText(moment.title_key, t) : t('appointment')} close={close} t={t}><Status resource={resource} t={t}>{moment && <><p className="muted">{new Date(moment.starts_at).toLocaleString()} — {new Date(moment.ends_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>{moment.scene_image_url && <Media src={moment.scene_image_url} alt={companion.name} className="result-media"/>}{moment.scene_audio_url && <Media src={moment.scene_audio_url} kind="audio"/>}<p className="prose">{moment.scene_situation || moment.opening || moment.invitation}</p>{!moment.opening && !started ? <><div className="preparation-actions">{(['talk', 'quiet', 'story', 'surprise'] as const).map(choice => <button className={`button ${moment.preparation === choice ? 'primary' : ''}`} disabled={busy} key={choice} onClick={() => action('prepare', { choice })}>{productText('date.prep.' + choice, t)}</button>)}</div><p className="prose">{moment.preparation_reaction}</p><button className="button primary" disabled={busy} onClick={() => action('start')}>{t('enter')}<ArrowRight size={16}/></button></> : <><div className="moment-chat"><Chat key={eventID} companion={companion} t={t} notify={notify} eventID={eventID}/></div><form className="form" onSubmit={async (e) => { e.preventDefault(); await action('artifact', { text: new FormData(e.currentTarget).get('text') }, 'PUT'); }}><label>{t('artifact')}<textarea name="text" required maxLength={500} rows={3} defaultValue={moment.user_text}/></label><button className="button" disabled={busy}>{t('save')}</button></form><p className="prose">{moment.artifact}</p><button className="text-button" disabled={busy} onClick={() => action('finish')}>{t('finish')}<Heart size={17}/></button><p className="prose">{moment.closing}</p></>}</>}</Status></Modal>;
}
function Preferences({ t, notify }: {
    t: T;
    notify: (e: unknown) => void;
}) {
    const contact = useResource('/v1/me/contact-preferences');
    const world = useResource('/v1/me/world-preferences');
    const deleted = useResource('/v1/companions-deleted');
    const [busy, setBusy] = useState(false);
    return <><section className="account-panel"><h2>{t('contact')}</h2><Status resource={contact} t={t}>{contact.data && <form className="form" onSubmit={async (e) => {
                e.preventDefault();
                const f = new FormData(e.currentTarget);
                setBusy(true);
                try {
                    await api('/v1/me/contact-preferences', { method: 'PUT', body: { daily_limit: Number(f.get('daily_limit')), minimum_gap_minutes: Number(f.get('minimum_gap_minutes')), quiet_enabled: f.get('quiet_enabled') === 'on', quiet_start: Number(f.get('quiet_start')), quiet_end: Number(f.get('quiet_end')) } });
                    notify(new Error(t('saved')));
                    contact.reload();
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}>{(['daily_limit', 'minimum_gap_minutes', 'quiet_start', 'quiet_end'] as const).map((key, i) => <label key={key}>{t((['dailyLimit', 'minimumGap', 'quietStart', 'quietEnd'] as const)[i])}<input type="number" min={i === 1 ? 30 : 0} max={i > 1 ? 23 : i === 0 ? 8 : 1440} name={key} required defaultValue={contact.data.preferences[key]}/></label>)}<label className="checkbox"><input type="checkbox" name="quiet_enabled" defaultChecked={contact.data.preferences.quiet_enabled}/>{t('quiet')}</label><button className="button" disabled={busy}>{t('save')}</button></form>}</Status></section><section className="account-panel"><h2>{t('world')}</h2><Status resource={world} t={t}>{world.data && <form className="form" onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                try {
                    await api('/v1/me/world-preferences', { method: 'PUT', body: Object.fromEntries(new FormData(e.currentTarget)) });
                    notify(new Error(t('saved')));
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}><label>{t('timezone')}<input name="timezone" defaultValue={world.data.timezone} required/></label><label>{t('region')}<input name="region_code" defaultValue={world.data.region_code} required maxLength={6}/></label><button className="button" disabled={busy}>{t('save')}</button></form>}</Status></section><Status resource={deleted} t={t}>{items(deleted.data).length > 0 && <section className="account-panel"><h2>{t('deletedCompanions')}</h2>{items(deleted.data).map(c => <div className="transaction" key={c.id}><span>{c.name}</span><button className="button" disabled={busy} onClick={async () => {
                    setBusy(true);
                    try {
                        await api(`/v1/companions/${c.id}/restore`, { method: 'POST' });
                        window.location.reload();
                    }
                    catch (e) {
                        notify(e);
                    }
                    finally {
                        setBusy(false);
                    }
                }}>{t('restore')}</button></div>)}</section>}</Status></>;
}
function GuestHome({ t, login, navigate }: {
    t: T;
    login: () => void;
    navigate: (section: Section) => void;
}) {
    const [draft, setDraft] = useState('');
    function begin(e: FormEvent) { e.preventDefault(); if (draft.trim())
        sessionStorage.setItem('vita.message-draft', draft); login(); }
    return <div className="workspace-start"><div className="start-center"><h1>{t('startTitle')}</h1><form className="start-composer" onSubmit={begin}><button type="button" className="icon-button" onClick={login} aria-label={t('attachment')}><Plus size={23} strokeWidth={1.5}/></button><input value={draft} onChange={e => setDraft(e.target.value)} placeholder={t('startPlaceholder')} aria-label={t('message')}/><div className="start-composer-tools"><span>Vita</span><button className="start-send" aria-label={t('send')}><ArrowUp size={20}/></button></div></form><div className="start-suggestions"><button onClick={login}><MessageCircle size={18}/><span>{t('startSuggestionChat')}</span></button><button onClick={() => navigate('stories')}><BookOpen size={18}/><span>{t('startSuggestionStory')}</span></button><button onClick={() => navigate('pets')}><PawPrint size={18}/><span>{t('startSuggestionPet')}</span></button></div></div></div>;
}
function checkoutAttempt(product: Entity) {
    const prior = sessionStorage.getItem('vita.paypal-attempt');
    let pending: Entity | null = null;
    try {
        pending = prior ? JSON.parse(prior) : null;
    }
    catch {
        sessionStorage.removeItem('vita.paypal-attempt');
    }
    if (!pending || pending.product_key !== product.key || pending.kind !== product.kind) {
        pending = { product_key: product.key, kind: product.kind, idempotency_key: crypto.randomUUID() };
        sessionStorage.setItem('vita.paypal-attempt', JSON.stringify(pending));
    }
    return pending;
}
function DraftCompanion({ t, close, back, done, notify }: {
    t: T;
    close: () => void;
    back: () => void;
    done: (id: string) => void;
    notify: (e: unknown) => void;
}) {
    const [busy, setBusy] = useState(false);
    const [draft, setDraft] = useState<Entity | null>(null);
    return <Modal title={t('generateCompanion')} close={close} t={t}><button className="text-button" onClick={back}><ArrowLeft size={16}/>{t('manual')}</button>{!draft ? <form className="form" onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                const f = new FormData(e.currentTarget);
                f.set('mode', (f.get('document') as File)?.size ? 'meet_file' : 'user_description');
                try {
                    setDraft(await api('/v1/companion-drafts', { method: 'POST', body: f }));
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}><label>{t('name')}<input name="character_name" required maxLength={100}/></label><label>{t('description')}<textarea name="description" rows={5} maxLength={4000}/></label><label>{t('document')}<input name="document" type="file" accept=".pdf,.docx,.txt"/></label><label>{t('upload')}<input name="image" type="file" accept="image/*" required/></label><button className="button primary" disabled={busy}>{busy ? t('loading') : t('generate')}</button></form> : <form className="form" onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                try {
                    const result = await api('/v1/companions/', { method: 'POST', body: { ...draft.profile, ...Object.fromEntries(new FormData(e.currentTarget)), avatar_media_id: draft.avatar_media_id, creation_source: draft.creation_source } });
                    done(result.id);
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}><Media src={draft.portrait_url} className="profile-portrait" alt={draft.profile.name}/><label>{t('name')}<input name="name" defaultValue={draft.profile.name} required/></label><label>{t('persona')}<textarea name="persona" rows={7} defaultValue={draft.profile.persona}/></label><button className="button primary" disabled={busy}>{t('newCompanion')}</button></form>}</Modal>;
}
function MemoryFavorite({ companionID, memoryID, t, notify }: {
    companionID: string;
    memoryID: string;
    t: T;
    notify: (e: unknown) => void;
}) {
    const resource = useResource(`/v1/companions/${companionID}/memories/`);
    const memory = items(resource.data, 'memories').find(m => m.id === memoryID);
    const [busy, setBusy] = useState(false);
    if (!memory || memory.readonly)
        return null;
    return <button className="text-button" type="button" disabled={busy} onClick={async () => {
            setBusy(true);
            try {
                await api(`/v1/companions/${companionID}/memories/${memoryID}/favorite`, { method: 'PUT', body: { favorite: !memory.is_favorite } });
                resource.reload();
            }
            catch (e) {
                notify(e);
            }
            finally {
                setBusy(false);
            }
        }}><Heart size={16} fill={memory.is_favorite ? 'currentColor' : 'none'}/>{t(memory.is_favorite ? 'unfavorite' : 'favorite')}</button>;
}
function StoryBackground({ t, close, done, notify }: {
    t: T;
    close: () => void;
    done: () => void;
    notify: (e: unknown) => void;
}) {
    const [busy, setBusy] = useState(false);
    return <Modal title={t('background')} close={close} t={t}><form className="form" onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            try {
                await api('/v1/story-backgrounds', { method: 'POST', body: Object.fromEntries(new FormData(e.currentTarget)) });
                done();
            }
            catch (e) {
                notify(e);
            }
            finally {
                setBusy(false);
            }
        }}>{([{ key: 'title', label: 'name' }, { key: 'synopsis', label: 'synopsis' }, { key: 'world_setting', label: 'worldSetting' }, { key: 'opening', label: 'opening' }, { key: 'genre', label: 'genre' }, { key: 'story_goal', label: 'storyGoal' }] as const).map(field => <label key={field.key}>{t(field.label)}<textarea name={field.key} required maxLength={field.key === 'title' ? 80 : 4000} rows={field.key === 'title' || field.key === 'genre' ? 1 : 3}/></label>)}<button className="button primary" disabled={busy}>{t('save')}</button></form></Modal>;
}
function StoryBoardAction({ story, t, notify, changed }: {
    story: Entity;
    t: T;
    notify: (e: unknown) => void;
    changed: () => Promise<void>;
}) {
    const [busy, setBusy] = useState(false);
    const requestKey = useRef<string | null>(null);
    const [panelCount, setPanelCount] = useState(4);
    if (!story.storyboard_unlocked)
        return null;
    return <div className="form"><p className="muted">{story.config?.storyboard_coins} {t('credits')}</p><select value={panelCount} aria-label={t('storyboard')} onChange={e => setPanelCount(Number(e.target.value))} disabled={!!requestKey.current}><option value={4}>4</option><option value={6}>6</option><option value={9}>9</option></select><button className="button" disabled={busy} onClick={async () => {
            if (!requestKey.current && !window.confirm(`${t('storyboard')} · ${story.config?.storyboard_coins} ${t('credits')}?`))
                return;
            setBusy(true);
            requestKey.current ||= crypto.randomUUID();
            try {
                await api(`/v1/stories/${story.id}/storyboards`, { method: 'POST', body: { idempotency_key: requestKey.current, panel_count: panelCount } });
                requestKey.current = null;
                await changed();
            }
            catch (e) {
                notify(e);
            }
            finally {
                setBusy(false);
            }
        }}>{busy ? t('loading') : requestKey.current ? t('retry') : t('storyboard')}<ArrowRight size={15}/></button></div>;
}
