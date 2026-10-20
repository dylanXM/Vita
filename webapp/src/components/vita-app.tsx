'use client';
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { ArrowDown, ArrowLeft, ArrowRight, ArrowUp, BookOpen, Check, Compass, Globe2, Heart, History, Menu, MessageCircle, MoreHorizontal, PanelLeft, PawPrint, Plus, Search, Sparkles, UserRound, X } from 'lucide-react';
import { api, ApiError, items, session, type Entity } from '../lib/api';
import GoogleSignIn from './google-sign-in';
import { Media, Modal } from './companion-ui';
import Select from './select';
import AccountMenu, { type Theme } from './account-menu';
import { OverlayProvider, Toast, useConfirm } from './overlays';
import { Form, Input, Textarea } from './form';
import Encounters from './encounters';
import { changed, useResource } from '../lib/companion-data';
import PetRoom from './pet-room';
import { exchangeGoogleCredential, type GoogleConsent } from '../lib/google-auth';
import { messages, localeNames, type Locale, type MessageKey, productText, displayDate } from '../lib/i18n';
type Section = 'encounters' | 'world' | 'chat' | 'journey' | 'explore' | 'stories' | 'pets';
type T = (key: MessageKey) => string;
const navigation = [{ id: 'world', Icon: Globe2 }, { id: 'chat', Icon: MessageCircle }, { id: 'journey', Icon: History }, { id: 'explore', Icon: Compass }] as const;
function Status({ resource, t, children }: {
    resource: ReturnType<typeof useResource>;
    t: T;
    children: ReactNode;
}) {
    if (resource.loading && resource.data == null)
        return <div className="state" role="status"><span className="spinner"/>{t('loading')}</div>;
    if (resource.error && resource.data == null)
        return <div className="state" role="alert"><p>{resource.error}</p><button className="button" onClick={resource.reload}>{t('retry')}</button></div>;
    return <>{resource.error && <div className="inline-error" role="alert">{resource.error}<button className="text-button" onClick={resource.reload}>{t('retry')}</button></div>}{children}</>;
}
function Empty({ t, children }: {
    t: T;
    children?: ReactNode;
}) { return <div className="state empty"><Sparkles size={28}/><p>{t('empty')}</p>{children}</div>; }
export default function VitaApp() { return <OverlayProvider><VitaWorkspace/></OverlayProvider>; }
function VitaWorkspace() {
    const [locale, setLocale] = useState<Locale>('zh-CN');
    const t: T = useCallback((key: MessageKey) => messages[locale][key], [locale]);
    const [section, setSection] = useState<Section>('world');
    const [authenticated, setAuthenticated] = useState(false);
    const [ready, setReady] = useState(false);
    const [auth, setAuth] = useState(false);
    const [create, setCreate] = useState(false);
    const [mobile, setMobile] = useState(false);
    const [collapsed, setCollapsed] = useState(false);
    const [theme, setTheme] = useState<Theme>('system');
    const [accountPanel, setAccountPanel] = useState<'profile' | 'feedback' | 'membership' | null>(null);
    const [selected, setSelected] = useState('');
    const [chatContext, setChatContext] = useState<Entity | null>(null);
    const [revision, setRevision] = useState(0);
    const [notice, setNotice] = useState({ message: '', id: 0 });
    const [query, setQuery] = useState('');
    const companions = useResource(authenticated ? '/v1/companions/' : null, 0, 12000);
    const me = useResource(authenticated ? '/v1/me' : null, revision);
    const credits = useResource(authenticated ? '/v1/me/credits' : null, revision);
    const people = items(companions.data).filter(c => c.creation_source !== 'ai_pet').sort((a, b) => Number(b.unread_count > 0) - Number(a.unread_count > 0) || (Date.parse(b.last_message_at) || 0) - (Date.parse(a.last_message_at) || 0));
    const current = people.find(c => c.id === selected) || people[0];
    useEffect(() => { if (current && current.id !== selected) setSelected(current.id); }, [current?.id, selected]);
    useEffect(() => {
        setAuthenticated(session.exists());
        setReady(true);
        const saved = localStorage.getItem('vita.locale');
        if (saved && Object.hasOwn(messages, saved))
            setLocale(saved as Locale);
        const savedTheme = localStorage.getItem('vita.theme');
        if (savedTheme === 'dark' || savedTheme === 'light') setTheme(savedTheme);
        const expired = () => { setAuthenticated(false); setSelected(''); setAuth(true); };
        const hash = () => {
            const value = window.location.hash.slice(1);
            if (value === 'membership' || value === 'account') { setAccountPanel(value === 'membership' || new URLSearchParams(window.location.search).has('checkout') ? 'membership' : 'profile'); setSection('world'); window.history.replaceState(null, '', '#world'); return; }
            if (['world', 'chat', 'journey', 'explore', 'stories', 'pets', 'encounters'].includes(value))
                setSection(value as Section);
        };
        hash();
        if (new URLSearchParams(window.location.search).has('checkout')) setAccountPanel('membership');
        window.addEventListener('hashchange', hash);
        window.addEventListener('vita:expired', expired);
        return () => { window.removeEventListener('hashchange', hash); window.removeEventListener('vita:expired', expired); };
    }, []);
    useEffect(() => {
        const media = window.matchMedia('(prefers-color-scheme: dark)');
        const apply = () => { document.documentElement.dataset.theme = (theme === 'system' ? media.matches : theme === 'dark') ? 'dark' : 'light'; };
        apply();
        media.addEventListener('change', apply);
        if (ready) localStorage.setItem('vita.theme', theme);
        return () => media.removeEventListener('change', apply);
    }, [theme, ready]);
    useEffect(() => { document.documentElement.lang = locale; document.documentElement.dir = locale === 'ar' ? 'rtl' : 'ltr'; localStorage.setItem('vita.locale', locale); window.dispatchEvent(new Event('vita:locale')); }, [locale]);
    useEffect(() => {
        if (!notice.message)
            return;
        const timer = setTimeout(() => setNotice(previous => ({ ...previous, message: '' })), 5500);
        return () => clearTimeout(timer);
    }, [notice]);
    const navigate = (next: Section) => { if (next !== 'chat') setChatContext(null); setSection(next); setMobile(false); setQuery(''); window.location.hash = next; };
    const refresh = () => { setRevision(n => n + 1); changed(); };
    const openChat = (id: string, context?: Entity) => { setChatContext(context ? { ...context, companion_id: id } : null); setSelected(id); navigate('chat'); };
    const requireAuth = (action: () => void) => {
        if (!authenticated)
            setAuth(true);
        else
            action();
    };
    const notify = (e: unknown) => {
        if (e instanceof ApiError && (e.action === 'open_credits' || e.action === 'open_subscription' || ['insufficient_credits', 'default_chat_trial_expired', 'friendship_inactive', 'ai_pet_plan_required'].includes(e.code || '') || e.code?.includes('requires_subscription'))) setAccountPanel('membership');
        const codeText: Record<string, string> = { character_image_invalid: 'companion.create.imageInvalid', character_image_required: 'companion.create.imageRequiredMessage', character_image_validation_unavailable: 'companion.create.imageValidationUnavailable', default_chat_trial_expired: 'accessRequired', friendship_inactive: 'accessRequired', companion_creation_requires_subscription: 'accessRequired', experience_requires_subscription: 'accessRequired', ai_pet_plan_required: 'accessRequired', date_slots_changed: 'experience.slots.changed', date_schedule_busy: 'experience.slots.changed', invalid_appointment: 'experience.slots.changed' };
        setNotice(previous => ({ id: previous.id + 1, message: e instanceof ApiError && codeText[e.code || ''] ? productText(codeText[e.code || ''], t) : e instanceof Error ? e.message : t('failed') }));
    };
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
        setAccountPanel(null);
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
      <div className="sidebar-people">{people.map(person => <button key={person.id} className={`person-link ${section === 'chat' && current?.id === person.id ? 'selected' : ''}`} onClick={() => openChat(person.id)}><Media src={person.portrait_url} alt={person.name} className="avatar"/><span>{person.name}<small>{person.last_message_type === 'voice' ? t('audio') : productText(person.last_message || person.occupation || '', t)}</small></span>{person.unread_count > 0 && <i className="unread">{person.unread_count}</i>}</button>)}{!people.length && <p className="sidebar-hint">{authenticated ? t('noCompanion') : t('loginRequired')}</p>}</div>
      <div className="sidebar-bottom"><button className="upgrade" onClick={() => requireAuth(() => setAccountPanel('membership'))}><Sparkles size={19}/><span>{t('subscription')}<small>{t('membershipHint')}</small></span><ArrowUp size={15}/></button><AccountMenu t={t} locale={locale} setLocale={setLocale} theme={theme} setTheme={setTheme} authenticated={authenticated} me={me.data} balance={credits.data?.balance} login={() => setAuth(true)} edit={() => setAccountPanel('profile')} feedback={() => setAccountPanel('feedback')} logout={logout}/></div>
    </aside>
    <div className="workspace"><header className="topbar"><div className="header-title"><button className={`icon-button mobile-menu ${collapsed ? 'show-expand' : ''}`} aria-label={t('menu')} onClick={() => { if (window.matchMedia('(max-width: 760px)').matches)
        setMobile(true); setCollapsed(false); }}><Menu size={21}/></button></div><div className="header-actions">{!authenticated && <button className="button small primary" onClick={() => setAuth(true)}>{t('login')}<ArrowRight size={14}/></button>}</div></header>
      <main id="main" className={`main-content ${section === 'chat' ? 'chat-main' : section === 'world' && !authenticated ? 'start-main' : ''}`}>
        {section === 'world' && (!authenticated ? <GuestHome t={t} login={() => setAuth(true)} navigate={navigate}/> : <><Heading title={t('world')} body={t('worldIntro')} eyebrow=""/><Status resource={companions} t={t}>{!people.length ? <Empty t={t}><button className="button primary" onClick={() => setCreate(true)}>{t('newCompanion')}</button></Empty> : <><div className="companion-switcher" aria-label={t('chooseCompanion')}>{people.map(c => <button className={`companion-tile ${current.id === c.id ? 'selected' : ''}`} aria-pressed={current.id === c.id} key={c.id} onClick={() => setSelected(c.id)}><Media src={c.portrait_url} alt={c.name}/><span><strong>{c.name}</strong><small>{productText(c.last_message || c.occupation || '', t)}</small></span>{c.unread_count > 0 && <i className="unread">{c.unread_count}</i>}</button>)}</div><World key={current.id} companion={current} t={t} revision={revision} onChat={openChat} notify={notify}/></>}</Status></>)}
        {section === 'chat' && (!authenticated ? <Guest t={t} login={() => setAuth(true)}/> : <Status resource={companions} t={t}>{current ? <Chat key={`${current.id}:${chatContext?.journey_visit_id || ''}`} companion={current} t={t} notify={notify} journeyVisitID={chatContext?.companion_id === current.id ? chatContext.journey_visit_id : undefined}/> : <Empty t={t}><button className="button primary" onClick={() => setCreate(true)}>{t('newCompanion')}</button></Empty>}</Status>)}
        {section === 'journey' && <><Heading title={t('journey')} body={t('journeyIntro')} eyebrow=""/><Journey authenticated={authenticated} people={people} t={t} login={() => setAuth(true)} query={query} setQuery={setQuery} notify={notify} onContinue={openChat} onWorld={id => { setSelected(id); navigate('world'); }}/></>}
        {section === 'explore' && <div className="explore-content"><Heading title={t('explore')} body={t('exploreIntro')} eyebrow=""/><div className="explore-list"><button className="explore-row" onClick={() => navigate('stories')}><span className="explore-thumbnail story-thumbnail"><BookOpen size={28} strokeWidth={1.3}/></span><span className="explore-row-copy"><strong>{t('stories')}</strong><span>{t('storiesIntro')}</span></span><ArrowRight size={18}/></button><button className="explore-row" onClick={() => navigate('pets')}><span className="explore-thumbnail"><img src="/assets/ai_pets/cat_ragdoll.png" alt=""/></span><span className="explore-row-copy"><strong>{t('pets')}</strong><span>{t('petsIntro')}</span></span><ArrowRight size={18}/></button></div><ExplorePosts authenticated={authenticated} t={t}/></div>}
        {section === 'encounters' && (authenticated ? <Encounters t={t} notify={notify} changed={changed}/> : <Guest t={t} login={() => setAuth(true)}/>)}
        {section === 'stories' && <><Heading title={t('stories')} body={t('storiesIntro')} eyebrow=""/>{authenticated ? <Stories t={t} people={people} notify={notify} refresh={refresh}/> : <Guest t={t} login={() => setAuth(true)}/>}</>}
        {section === 'pets' && <><Heading title={t('pets')} body={t('petsIntro')} eyebrow=""/>{authenticated ? <Pets t={t} notify={notify} refresh={refresh}/> : <Guest t={t} login={() => setAuth(true)}/>}</>}

      </main>
    </div>
    {notice.message && <Toast key={notice.id} message={notice.message} t={t} close={() => setNotice(previous => ({ ...previous, message: '' }))}/> }
    {auth && <Auth t={t} locale={locale} close={() => setAuth(false)} done={() => { setAuthenticated(true); setAuth(false); refresh(); if (sessionStorage.getItem('vita.message-draft'))
        navigate('chat'); }} notify={notify}/>}
    {accountPanel && authenticated && <Modal title={t(accountPanel === 'profile' ? 'editProfile' : accountPanel === 'feedback' ? 'feedback' : 'subscription')} close={() => setAccountPanel(null)} t={t}><Account mode={accountPanel} t={t} me={me.data} revision={revision} refresh={refresh} notify={notify}/></Modal>}
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
        <Form t={t} className="form auth-form" onSubmit={submit}>
            {mode!=='googleConsent'&&<label>{t('email')}<Input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="email" readOnly={mode==='verify'} disabled={busy}/></label>}
            {mode==='verify'?<label>{t('code')}<Input name="code" required pattern="[0-9]{6}" inputMode="numeric" autoComplete="one-time-code" maxLength={6} disabled={busy}/></label>:mode!=='googleConsent'&&<label>{t('password')}<Input type="password" name="password" required minLength={mode==='register'?6:1} maxLength={72} autoComplete={mode==='register'?'new-password':'current-password'} disabled={busy}/></label>}
            {needsConsent&&<><label>{t('invitationCode')}<Input value={inviteCode} onChange={e=>setInviteCode(e.target.value)} disabled={busy}/></label><Status resource={legal} t={t}>{docs?.privacy&&docs?.terms?<><details><summary>{t('privacy')}</summary><div className="legal-copy">{docs.privacy.content}</div></details><details><summary>{t('terms')}</summary><div className="legal-copy">{docs.terms.content}</div></details><label className="checkbox"><Input type="checkbox" checked={accepted} onChange={e=>setAccepted(e.target.checked)} required disabled={busy}/>{t('consent')} {t('privacy')} / {t('terms')}</label></>:<p className="muted">{t('noLegal')}</p>}</Status></>}
            <button className="button primary full" disabled={busy||(needsConsent&&(!accepted||!docs?.privacy?.version||!docs?.terms?.version))}>{busy?t('loading'):t(mode==='login'?'login':mode==='verify'?'verify':mode==='googleConsent'?'googleComplete':'sendCode')}<ArrowRight size={17}/></button>
            <button type="button" className="text-button" disabled={busy} onClick={()=>{pendingGoogle.current=null;setMode(mode==='login'?'register':'login');setAccepted(false)}}>{t(mode==='login'?'register':'login')}</button>
        </Form>
    </Modal>;
}
function CreateCompanion({ t, close, done, notify }: {
    t: T;
    close: () => void;
    done: (id: string) => void;
    notify: (e: unknown) => void;
}) {
    const options = useResource('/v1/companion-options');
    const [portrait, setPortrait] = useState('');
    const [role, setRole] = useState('');
    const [stage, setStage] = useState('');
    const [tags, setTags] = useState<string[]>([]);
    const [step, setStep] = useState(0);
    const creationForm = useRef<HTMLFormElement>(null);
    function nextStep() {
        const invalid = creationForm.current?.querySelector<HTMLInputElement | HTMLTextAreaElement>('.creation-fields:not([hidden]) :invalid');
        if (invalid) invalid.reportValidity(); else setStep(1);
    }
    const [busy, setBusy] = useState(false);
    const [media, setMedia] = useState('');
    const [draftMode, setDraftMode] = useState(false);
    const portraits = items(options.data, 'portraits').filter(p => p.gender !== 'pet');
    async function submit(e: FormEvent<HTMLFormElement>) {
        e.preventDefault();
        if (busy) return;
        if (step === 0) { nextStep(); return; }
        setBusy(true);
        const f = new FormData(e.currentTarget);
        try {
            const data = await api('/v1/companions/', { method: 'POST', body: { name: f.get('name'), persona: f.get('persona'), city: f.get('city'), occupation: f.get('occupation'), interests: f.get('interests'), personality_tags: tags, gender: role || items(options.data, 'relationships')[0]?.key, relationship_stage: stage || items(options.data, 'relationships').find(r => r.key === role)?.default_stage || items(options.data, 'relationships')[0]?.default_stage, creation_source: 'tags_portrait', ...(media ? { avatar_media_id: media } : { portrait_id: portrait }) } });
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
    return <Modal title={t('newCompanion')} close={close} t={t}><button className="text-button" onClick={() => setDraftMode(true)}><Sparkles size={16}/>{t('generateCompanion')}</button><p className="muted">{t('createIntro')}</p><div className="creation-steps"><button className={step === 0 ? 'selected' : ''} onClick={() => setStep(0)}>{t('profile')}</button><button className={step === 1 ? 'selected' : ''} onClick={nextStep}>{t('relationship')}</button></div><Form t={t} ref={creationForm} className="form" onSubmit={submit}><div className="creation-fields" hidden={step !== 0}><label>{t('name')}<Input name="name" required maxLength={100}/></label><label>{t('persona')}<Textarea name="persona" rows={4} maxLength={4000}/></label><div className="form-row"><label>{t('city')}<Input name="city"/></label><label>{t('occupation')}<Input name="occupation"/></label></div><label>{t('interests')}<Input name="interests" maxLength={1000}/></label><label>{productText('companion.create.traits', t)}</label><div className="scene-choices">{(Array.isArray(options.data?.personality_tags) ? options.data.personality_tags : []).map((tag: string) => <button type="button" key={tag} className={`button ${tags.includes(tag) ? 'primary' : ''}`} aria-pressed={tags.includes(tag)} disabled={!tags.includes(tag) && tags.length >= 8} onClick={() => setTags(old => old.includes(tag) ? old.filter(value => value !== tag) : [...old, tag])}>{productText(`tag.${tag}`, t)}</button>)}</div></div><div className="creation-fields" hidden={step !== 1}><label>{t('relationship')}<Select aria-label={t('relationship')} name="gender" value={role || items(options.data, 'relationships')[0]?.key || ''} onChange={e => { setRole(e.target.value); setStage(''); }}>{items(options.data, 'relationships').map(r => <option value={r.key} key={r.key}>{productText('relation.' + r.key, t)}</option>)}</Select></label><label>{t('closeness')}<Select aria-label={t('closeness')} value={stage || (items(options.data, 'relationships').find(r => r.key === role) || items(options.data, 'relationships')[0])?.default_stage || ''} onChange={e => setStage(e.target.value)}>{((items(options.data, 'relationships').find(r => r.key === role) || items(options.data, 'relationships')[0])?.stages || []).map((key: string) => <option key={key} value={key}>{productText(`stage.${key}`, t)}</option>)}</Select></label><label>{t('portrait')}</label><Status resource={options} t={t}><div className="portrait-picker">{portraits.map(p => <button type="button" className={portrait === p.id && !media ? 'chosen' : ''} key={p.id} onClick={() => { setPortrait(p.id); setMedia(''); const selectedRole = items(options.data, 'relationships').find(r => r.key === role) || items(options.data, 'relationships')[0]; if (selectedRole?.gender_hint && p.gender && selectedRole.gender_hint !== p.gender && selectedRole.paired_role) { setRole(selectedRole.paired_role); setStage(''); } }} aria-label={p.name || t('selectPortrait')}><Media src={p.image_url} alt={p.name}/></button>)}</div></Status><label className="upload-label">{media ? <Check size={17}/> : <Plus size={17}/>} {t('upload')}<Input type="file" accept="image/*" disabled={busy} onChange={async (e) => {
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
        }}/></label></div>{step === 0 ? <button type="button" className="button primary" onClick={nextStep}>{t('next')}<ArrowRight size={16}/></button> : <button className="button primary" disabled={busy || options.loading || !!options.error || !items(options.data, 'relationships').length || (!portrait && !media)}>{busy ? t('loading') : t('newCompanion')}<ArrowRight size={16}/></button>}</Form></Modal>;
}
function World({ companion, t, revision, onChat, notify }: {
    companion: Entity;
    t: T;
    revision: number;
    onChat: (id: string) => void;
    notify: (e: unknown) => void;
}) {
    const resource = useResource(`/v1/companions/${companion.id}/world/scene`, revision, 30000);
    const [momentID, setMomentID] = useState('');
    const [experience, setExperience] = useState(false);
    const scene = resource.data;
    return <Status resource={resource} t={t}>{scene && <><div className="world-card"><div className="world-portrait"><Media src={companion.portrait_url} alt={companion.name}/><span className="world-tag"><span className="live-dot"/>{companion.city || productText(scene.place?.title || 'Vita', t)}</span></div><div className="world-story"><span className="scene-badge">{productText(`stage.${companion.relationship_stage || 'stranger'}`, t)}</span><div className="eyebrow">{t('today')} · {scene.local_date}</div><h2>{companion.name}<span>{productText(scene.place?.title || '', t)}</span></h2><p className="world-description">{scene.event?.description || scene.place?.description || companion.persona}</p><span className="world-phase">{productText(`world.phase.${scene.phase || 'quiet'}`, t)}</span>{scene.event?.title && <div className="activity"><span className="live-dot"/>{productText(scene.event.title, t)}</div>}<div className="world-actions"><button className="button" onClick={() => setExperience(true)}>{t('experiences')}</button><button className="text-button" onClick={() => onChat(companion.id)}>{t('continueChat')}<ArrowRight size={16}/></button></div></div></div>{scene.today_visit?.reaction && <div className="reaction"><Sparkles size={20}/><p>{scene.today_visit.reaction}</p><button className="text-button" onClick={() => onChat(companion.id)}>{t('continueChat')}<ArrowRight size={16}/></button></div>}{scene.appointment && <button className="appointment-banner" onClick={() => setMomentID(scene.appointment.id)}><BookOpen size={21}/><span>{productText(scene.appointment.title_key, t)}<small>{displayDate(scene.appointment.starts_at)}</small></span><ArrowRight size={18}/></button>}{momentID && <Moment companion={companion} eventID={momentID} t={t} notify={notify} close={() => setMomentID('')}/>}<div className="world-bottom">{scene.recent_gift && Date.now() - Date.parse(scene.recent_gift.created_at) < 48 * 3600000 && <article className="info-card gift-card"><Sparkles size={22}/><h3>{productText(scene.recent_gift.name_key || scene.recent_gift.product_key || 'experiences', t)}</h3><p>{scene.recent_gift.emoji} · {displayDate(scene.recent_gift.created_at, 'date')}</p></article>}<article className="info-card"><span className="eyebrow">{t('next')}</span><h3>{scene.next_event?.title || companion.occupation || companion.name}</h3><p>{scene.next_event?.description || companion.interests || t('worldIntro')}</p></article><article className="info-card"><span className="eyebrow">{t('memories')}</span>{items(scene, 'memories').length ? items(scene, 'memories').slice(0, 2).map(m => <p key={m.id}>{m.content}</p>) : <p>{t('journeyIntro')}</p>}</article>{items(scene, 'connections').length > 0 && <article className="info-card"><span className="eyebrow">{productText('world.connections', t)}</span>{items(scene, 'connections').map(person => <p key={person.id}>{person.name}</p>)}</article>}</div>{experience && <Experiences companion={companion} t={t} notify={notify} close={() => setExperience(false)} onMoment={id => { setExperience(false); setMomentID(id); }}/>}</>}</Status>;
}
function Chat({ companion, t, notify, eventID, readOnly = false, sceneKind = '', spendID, journeyVisitID }: {
    companion: Entity; t: T; notify: (e: unknown) => void; eventID?: string;
    readOnly?: boolean; sceneKind?: string; spendID?: string; journeyVisitID?: string;
}) {
    const appointments = useResource(!eventID && !spendID ? '/v1/companions/appointments' : null, 0, 30000);
    const [profile, setProfile] = useState(false);
    const [experiences, setExperiences] = useState(false);
    const [transfer, setTransfer] = useState(false);
    const [momentID, setMomentID] = useState('');
    const [conversation, setConversation] = useState<Entity | null>(null);
    const [messages, setMessages] = useState<Entity[]>([]);
    const [count, setCount] = useState(50);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [busy, setBusy] = useState(false);
    const [pending, setPending] = useState(false);
    const [replyFailed, setReplyFailed] = useState(false);
    const [text, setText] = useState(() => typeof window !== 'undefined' && !eventID && !spendID ? sessionStorage.getItem('vita.message-draft') || '' : '');
    const [version, setVersion] = useState(0);
    const viewport = useRef<HTMLDivElement>(null);
    const follow = useRef(true);
    const mutationEpoch = useRef(0);
    const query = eventID ? `channel=date&event_id=${encodeURIComponent(eventID)}` : 'channel=chat';
    useEffect(() => {
        let active = true;
        let running = false;
        let timer: ReturnType<typeof setTimeout>;
        let c: Entity | null = null;
        let signature = '';
        const controller = new AbortController();
        const load = async () => {
            const dialogs = document.querySelectorAll<HTMLDialogElement>('dialog[open]');
            const top = dialogs.item(dialogs.length - 1);
            if (!active || running) return;
            clearTimeout(timer);
            if (document.hidden || (top && viewport.current && !top.contains(viewport.current))) { timer = setTimeout(load, 4000); return; }
            running = true;
            try {
                if (!c) {
                    c = await api('/v1/conversations/', { method: 'POST', body: { companion_id: companion.id, ...(eventID ? { date_event_id: eventID } : {}) }, signal: controller.signal });
                    if (!active) return;
                    setConversation(c);
                }
                const epoch = mutationEpoch.current;
                const [data, status] = await Promise.all([
                    api(`/v1/conversations/${c!.conversation_id}/messages?${query}`, { signal: controller.signal }),
                    api(`/v1/conversations/${c!.conversation_id}/reply-status?${query}`, { signal: controller.signal }),
                ]);
                if (!active || epoch !== mutationEpoch.current) return;
                const list = spendID ? items(data).filter(m => m.payload?.shared_experience_spend_id === spendID) : items(data);
                setMessages(list);
                setPending(['pending', 'processing', 'queued'].includes(status.status));
                setReplyFailed(status.status === 'failed');
                setError('');
                const next = `${list.length}:${list.at(-1)?.id || ''}`;
                if (next !== signature) {
                    signature = next;
                    changed();
                }
            } catch (e) {
                if (active) setError(e instanceof Error ? e.message : '');
            } finally {
                running = false;
                if (active) { setLoading(false); timer = setTimeout(load, 4000); }
            }
        };
        const resume = () => { if (!document.hidden) { c = null; void load(); } };
        const refreshMessages = () => { void load(); };
        void load();
        document.addEventListener('visibilitychange', resume);
        window.addEventListener('focus', resume);
        window.addEventListener('vita:locale', resume);
        window.addEventListener('vita:chat-refresh', refreshMessages);
        return () => {
            active = false; controller.abort(); clearTimeout(timer);
            document.removeEventListener('visibilitychange', resume);
            window.removeEventListener('focus', resume);
            window.removeEventListener('vita:locale', resume);
            window.removeEventListener('vita:chat-refresh', refreshMessages);
        };
    }, [companion.id, eventID, spendID, query, version]);
    useEffect(() => {
        if (follow.current && viewport.current) viewport.current.scrollTop = viewport.current.scrollHeight;
    }, [messages, pending]);
    const reloadMessages = () => window.dispatchEvent(new Event('vita:chat-refresh'));
    async function sendContent(content: string, mediaID?: string, sceneAction?: string) {
        if ((!content.trim() && !mediaID) || !conversation || busy || readOnly || conversation.can_send === false || companion.can_chat === false) return;
        setBusy(true);
        try {
            const result = await api(`/v1/conversations/${conversation.conversation_id}/messages`, {
                method: 'POST', body: { ...(mediaID ? { message_type: 'voice', media_id: mediaID } : { message_type: 'text', content }), ...(eventID ? { life_event_id: eventID } : {}), ...(spendID ? { shared_experience_spend_id: spendID } : {}), ...(sceneAction ? { scene_action: sceneAction } : {}), ...(journeyVisitID ? { journey_visit_id: journeyVisitID } : {}) },
            });
            mutationEpoch.current++;
            const delivered = [result.user_message, result.companion_message].filter((m): m is Entity => !!m?.id);
            setMessages(previous => [...previous, ...delivered.filter(m => !previous.some(old => old.id === m.id))]);
            if (!mediaID) { setText(''); if (!eventID && !spendID) sessionStorage.removeItem('vita.message-draft'); }
            follow.current = true;
            setPending(['pending', 'processing', 'queued'].includes(result.reply_status));
            setReplyFailed(!!result.agent_error);
            reloadMessages(); changed();
        } catch (e) { notify(e); } finally { setBusy(false); }
    }
    const latest = messages.filter(m => m.sender_type === 'assistant' && m.message_type !== 'scene_image').at(-1);
    const suggestions = messages.at(-1)?.sender_type === 'assistant' && Array.isArray(latest?.payload?.scene_actions) ? latest.payload.scene_actions.filter((action: Entity) => typeof action.label === 'string' && typeof action.message === 'string').slice(0, 2) : [];
    const choices = (sceneKind.includes('cafe') ? ['coffee', 'tea', 'toast'] : sceneKind.includes('cinema') ? ['romance', 'mystery', 'pause'] : (sceneKind.includes('dance') || sceneKind === 'ballroom') ? ['dance', 'slow_dance', 'terrace'] : sceneKind.includes('restaurant') ? ['dinner', 'dessert', 'toast'] : []).filter(choice => !messages.some(m => m.sender_type === 'user' && m.delivery_status !== 'failed' && m.payload?.scene_action === choice));
    return <div className="conversation">
        <div className="conversation-head"><Media src={companion.portrait_url} alt={companion.name} className="avatar"/><div><h2>{companion.name}</h2><small>{conversation?.companion_status?.title || companion.occupation}</small></div><span className="conversation-meta">{companion.city}</span>{!eventID && <><button className="icon-button" aria-label={t('transfer')} onClick={() => setTransfer(true)}><Heart size={19}/></button><button className="icon-button" aria-label={t('experiences')} onClick={() => setExperiences(true)}><Sparkles size={19}/></button><button className="icon-button" aria-label={t('details')} onClick={() => setProfile(true)}><MoreHorizontal size={20}/></button></>}</div>
        <div className="chat-appointments">{items(appointments.data).filter(a => a.companion_id === companion.id).map(a => <button className="appointment-banner" key={a.id} onClick={() => setMomentID(a.id)}><BookOpen size={20}/><span>{productText(a.title_key, t)}<small>{displayDate(a.starts_at)}</small></span><ArrowRight size={18}/></button>)}</div>
        <div className="messages" ref={viewport} onScroll={e => { const el = e.currentTarget; follow.current = el.scrollHeight - el.scrollTop - el.clientHeight < 60; }} aria-busy={loading}>
            {messages.length > count && <button className="button load-more" onClick={() => {
                const el = viewport.current; const height = el?.scrollHeight || 0;
                follow.current = false; setCount(n => n + 50);
                requestAnimationFrame(() => { if (el) el.scrollTop += el.scrollHeight - height; });
            }}>{t('more')}</button>}
            {loading && <div className="state">{t('loading')}</div>}
            {error && <div className="inline-error" role="alert">{error}<button className="text-button" onClick={() => setVersion(n => n + 1)}>{t('retry')}</button></div>}
            {!loading && !error && !messages.length && <div className="conversation-empty"><h1>{t('chatEmpty')}</h1><p>{t('chatIntro')}</p></div>}
            {messages.slice(-count).map(m => <article className={`message ${m.sender_type === 'user' ? 'user-message' : 'companion-message'}`} key={m.id}>
                <span className="message-author">{m.sender_type === 'user' ? t('account') : companion.name}</span>
                <MessageContent message={m} companion={companion} t={t} notify={notify} onMoment={setMomentID} canConfirm={!readOnly} outcomeSaved={messages.some(saved => saved.payload?.experience_outcome && ((m.payload?.shared_experience_spend_id && saved.payload.shared_experience_spend_id === m.payload.shared_experience_spend_id) || (m.life_event_id && saved.life_event_id === m.life_event_id)))}/>
                <time>{displayDate(m.created_at, 'time', { hour: '2-digit', minute: '2-digit' })}</time>
                {m.delivery_status === 'failed' && <small className="inline-error">{t('failed')}</small>}
            </article>)}
            {pending && <div className="replying" role="status"><span className="spinner"/>{t('replying')}</div>}
            {replyFailed && !readOnly && <div className="inline-error">{t('replyFailed')}<button className="text-button" disabled={busy} onClick={async () => {
                if (!conversation) return; setBusy(true);
                try { await api(`/v1/conversations/${conversation.conversation_id}/reply-status/retry`, { method: 'POST', body: eventID ? { life_event_id: eventID } : {} }); setReplyFailed(false); setPending(true); reloadMessages(); }
                catch (e) { notify(e); } finally { setBusy(false); }
            }}>{t('retry')}</button></div>}
        </div>
        <div className="composer-wrap">{readOnly ? <p className="composer-note">{t('momentEnded')}</p> : (conversation?.can_send === false || companion.can_chat === false) ? <div className="access-banner"><p>{t('accessRequired')}</p><a className="button primary" href="#membership">{t('manage')}</a></div> : <>
            {(eventID || spendID) && latest?.payload?.scene_situation && <p className="scene-narration">{latest.payload.scene_situation}</p>}{suggestions.length > 0 && <div className="scene-choices">{suggestions.map((action: Entity) => <button className="button" key={action.label} disabled={busy || pending} onClick={() => void sendContent(action.message)}>{action.label}</button>)}</div>}{eventID && <div className="scene-choices">{choices.map(choice => <button className="button" key={choice} disabled={busy || pending || !conversation} onClick={() => void sendContent(productText(`date.scene.action.${choice}`, t), undefined, choice)}>{productText(`date.scene.${choice}`, t)}</button>)}</div>}
            <Form t={t} className="composer" onSubmit={e => { e.preventDefault(); void sendContent(text); }}><Textarea aria-label={t('message')} value={text} maxLength={4000} onChange={e => { setText(e.target.value); if (!eventID && !spendID) sessionStorage.setItem('vita.message-draft', e.target.value); }} placeholder={t('message')} rows={2} onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); e.currentTarget.form?.requestSubmit(); } }}/>
                <div className="composer-bottom"><label className="icon-button attachment" title={t('attachment')}><Plus size={21}/><span className="sr-only">{t('attachment')}</span><Input type="file" accept="audio/*" disabled={busy || !conversation} onChange={async e => {
                    const input = e.currentTarget; const file = input.files?.[0]; if (!file) return;
                    setBusy(true);
                    let mediaID = '';
                    try { const form = new FormData(); form.set('file', file); form.set('kind', 'audio'); const uploaded = await api('/v1/media/upload', { method: 'POST', body: form }); mediaID = uploaded.id; }
                    catch (error) { notify(error); } finally { setBusy(false); input.value = ''; }
                    if (mediaID) await sendContent('', mediaID);
                }}/></label><span>Vita · {companion.name}</span><button className="send-button" disabled={!text.trim() || busy || !conversation} aria-label={t('send')}><ArrowUp size={20}/></button></div>
            </Form></>}<p className="composer-note">{t('chatIntro')}</p></div>
        {profile && <CompanionProfile companion={companion} t={t} notify={notify} close={() => setProfile(false)}/>}
        {transfer && <Transfer companion={companion} t={t} notify={notify} close={() => setTransfer(false)} done={reloadMessages}/>}
        {experiences && <Experiences companion={companion} t={t} notify={notify} close={() => setExperiences(false)} onMoment={id => { setExperiences(false); setMomentID(id); }}/>}
        {momentID && <Moment companion={companion} eventID={momentID} t={t} notify={notify} close={() => setMomentID('')}/>}
    </div>;
}
function MessageContent({ message: m, companion, t, notify, onMoment, outcomeSaved, canConfirm }: { message: Entity; companion: Entity; t: T; notify: (e: unknown) => void; onMoment: (id: string) => void; outcomeSaved: boolean; canConfirm: boolean }) {
    const payload = m.payload || {};
    const [busy, setBusy] = useState(false);
    const [confirmed, setConfirmed] = useState(false);
    const proposal = payload.experience_proposal;
    const outcome = payload.experience_outcome;
    return <>
        {m.message_type === 'transfer' ? <div className="gesture-card"><Heart size={25}/><strong>{payload.coins ?? m.content} {t('credits')}</strong><span>{t('transfer')}</span></div> : m.message_type === 'gift' || m.source === 'paid_gift' ? <div className="gift-card"><Sparkles size={30}/><strong>{productText(payload.name_key || m.content || 'experiences', t)}</strong><span>{t('giftReceived')}</span></div> : m.content && <p>{m.source?.startsWith('paid_') ? productText(m.content, t) : m.content}</p>}
        {m.media_url && <Media src={m.media_url} kind={m.message_type} alt={t('image')} className="message-media"/>}
        {m.life_event_id && m.source?.startsWith('paid_date') && <button className="button" onClick={() => onMoment(m.life_event_id)}>{t('viewMoment')}<ArrowRight size={16}/></button>}
        {(proposal || outcome) && <div className="keepsake-card"><span className="eyebrow">{t(outcome || confirmed || outcomeSaved ? 'artifact' : 'jointDecision')}</span><h3>{(outcome || proposal).title}</h3><p>{(outcome || proposal).challenge}</p><p>{(outcome || proposal).decision}</p><p>{(outcome || proposal).note}</p>{proposal && canConfirm && !confirmed && !outcome && !outcomeSaved && <Form t={t} className="form" onSubmit={async e => {
            e.preventDefault(); setBusy(true);
            try { await api(`/v1/companions/${companion.id}/experience-outcome`, { method: 'POST', body: { ...(payload.shared_experience_spend_id ? { spend_id: payload.shared_experience_spend_id } : { event_id: m.life_event_id }), proposal_message_id: m.id, title: new FormData(e.currentTarget).get('title') } }); setConfirmed(true); window.dispatchEvent(new Event('vita:chat-refresh')); changed(); }
            catch (error) { notify(error); } finally { setBusy(false); }
        }}><label>{t('nameMoment')}<Input name="title" required maxLength={80} defaultValue={proposal.title}/></label><button className="button primary" disabled={busy}>{t('confirmDecision')}</button></Form>}</div>}
    </>;
}
function Transfer({ companion, t, close, done, notify }: { companion: Entity; t: T; close: () => void; done: () => void; notify: (e: unknown) => void }) {
    const credits = useResource('/v1/me/credits');
    const storageKey = `vita.transfer.${companion.id}`;
    const [attempt, setAttempt] = useState<Entity | null>(() => {
        try { return JSON.parse(sessionStorage.getItem(storageKey) || 'null'); } catch { return null; }
    });
    const [amount, setAmount] = useState(() => attempt?.coins || 10);
    const [busy, setBusy] = useState(false);
    return <Modal title={t('transfer')} close={() => { if (!busy) close(); }} t={t}><p className="muted">{companion.name} · {credits.data?.balance ?? '—'} {t('credits')}</p>{attempt && <p className="access-banner">{t('requestUnconfirmed')}</p>}<div className="scene-choices">{[10, 30, 100].map(value => <button className={`button ${amount === value ? 'primary' : ''}`} key={value} disabled={busy || !!attempt} onClick={() => setAmount(value)}>{value} {t('credits')}</button>)}</div><button className="button primary full" disabled={busy} onClick={async () => {
        if (busy) return;
        const request = attempt || { coins: amount, request_key: crypto.randomUUID() };
        setAttempt(request); sessionStorage.setItem(storageKey, JSON.stringify(request)); setBusy(true);
        try { await api(`/v1/companions/${companion.id}/transfers`, { method: 'POST', body: request }); sessionStorage.removeItem(storageKey); changed(); done(); close(); }
        catch (error) {
            if (error instanceof ApiError && error.status < 500 && error.code !== 'transfer_duplicate') { setAttempt(null); sessionStorage.removeItem(storageKey); }
            notify(error);
        } finally { setBusy(false); }
    }}>{t(busy ? 'loading' : attempt ? 'retry' : 'confirmPurchase')}</button></Modal>;
}
function Journey({ authenticated, people, t, login, query, setQuery, notify, onWorld, onContinue }: {
    authenticated: boolean;
    people: Entity[];
    t: T;
    login: () => void;
    onWorld: (id: string) => void;
    onContinue: (id: string, context?: Entity) => void;
    query: string;
    setQuery: (s: string) => void;
    notify: (e: unknown) => void;
}) {
    const confirm = useConfirm(t);
    const [selected, setSelected] = useState('');
    const [offset, setOffset] = useState(0);
    const [all, setAll] = useState<Entity[]>([]);
    const [detail, setDetail] = useState<Entity | null>(null);
    const [busy, setBusy] = useState(false);
    const [search, setSearch] = useState('');
    const [moment, setMoment] = useState<Entity | null>(null);
    const [experience, setExperience] = useState<Entity | null>(null);
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
            setAll([]);
            resource.reload();
        }
        catch (e) {
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    return <><div className="section-toolbar"><label className="search-field"><Search size={17}/><Input aria-label={t('search')} placeholder={t('search')} value={query} onChange={e => setQuery(e.target.value)}/></label><Select aria-label={t('chooseCompanion')} value={selected} onChange={e => { setSelected(e.target.value); setOffset(0); setAll([]); }}><option value="">{t('all')}</option>{people.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</Select></div><Status resource={resource} t={t}>{all.length ? <div className="memory-grid">{all.map(m => <button className="memory-card" key={m.id} onClick={() => m.metadata?.event_id && ['experience_appointment', 'shared_experience'].includes(m.type) ? setMoment(m) : m.metadata?.spend_id ? setExperience(m) : setDetail(m)}><span className="memory-date">{displayDate(m.event_time, 'date')}</span><h3>{productText(m.title || '', t) || m.companion?.name}</h3><p>{m.content}</p><span className="memory-author"><Heart size={14}/>{m.companion?.name}<ArrowRight size={15}/></span></button>)}</div> : <Empty t={t}/>}</Status>{resource.data?.has_more && <button className="button load-more" onClick={() => setOffset(resource.data.next_offset)}>{t('more')}<ArrowDown size={15}/></button>}{detail && <Modal title={detail.title || detail.companion?.name || t('memories')} close={() => setDetail(null)} t={t}>{detail.readonly ? <>{detail.type === 'world_visit' && detail.metadata?.portrait_url && <Media src={detail.metadata.portrait_url} alt={detail.companion?.name} className="visit-portrait"/>}<p className="prose">{detail.content}</p><p className="prose">{detail.metadata?.reaction}</p><p className="prose">{detail.metadata?.follow_up}</p><small className="muted">{t('readonly')}</small>{detail.type === 'world_visit' && <button className="button primary" onClick={() => { sessionStorage.setItem('vita.message-draft', productText(detail.metadata?.choice === 'ask' ? 'journey.continueAskDraft' : 'journey.continueStayDraft', t)); setDetail(null); onContinue(detail.companion.id, { journey_visit_id: detail.id }); }}>{productText('journey.continueThatDay', t)}</button>}{detail.type === 'world_visit' && <button className="button" onClick={() => { setDetail(null); onWorld(detail.companion.id); }}>{t('enter')}<ArrowRight size={16}/></button>}</> : <Form t={t} className="form" onSubmit={e => { e.preventDefault(); void modify('PUT', { content: new FormData(e.currentTarget).get('content') }); }}><Textarea name="content" defaultValue={detail.content} required maxLength={500} rows={8}/><MemoryFavorite companionID={detail.companion?.id || detail.companion_id} memoryID={detail.id} t={t} notify={notify}/><div className="form-row"><button className="button primary" disabled={busy}>{t('save')}</button><button type="button" className="button" disabled={busy} onClick={async () => {
                    if ((await confirm(t('confirmDelete'))))
                        void modify('DELETE');
                }}>{t('delete')}</button></div></Form>}</Modal>}{moment && <Moment companion={people.find(p => p.id === moment.companion.id) || moment.companion} eventID={moment.metadata.event_id} t={t} notify={notify} close={() => setMoment(null)}/>} {experience && <Modal wide title={productText(experience.title || 'experiences', t)} close={() => setExperience(null)} t={t}>{experience.metadata?.media_url && <Media src={experience.metadata.media_url} alt={experience.companion.name} className="result-media"/>}<p className="prose">{experience.metadata?.outcome?.decision || experience.content}</p><div className="moment-chat"><Chat companion={people.find(p => p.id === experience.companion.id) || experience.companion} t={t} notify={notify} spendID={experience.metadata.spend_id}/></div></Modal>}</>;
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
    const generatingStoryboard = !!detail && items(detail, 'storyboards').some(board => ['pending', 'processing', 'generating'].includes(board.status));
    useEffect(() => {
        if (!generatingStoryboard || !detail?.id) return;
        const id = detail.id;
        let active = true;
        let running = false;
        const timer = setInterval(async () => {
            if (document.hidden || running) return;
            running = true;
            try { const story = await api(`/v1/stories/${id}`); if (active) setDetail(story); } catch { /* Keep the current story; retry on the next tick. */ } finally { running = false; }
        }, 5000);
        return () => { active = false; clearInterval(timer); };
    }, [detail?.id, generatingStoryboard]);
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
                }}><BookOpen size={22}/><h3>{s.title}</h3><p>{s.companion?.name}</p><span className="memory-author">{t('read')}<ArrowRight size={16}/></span></button>)}</div></>}</Status><div className="section-toolbar"><h2>{t('startStory')}</h2><button className="text-button" onClick={() => setCustomBackground(true)}><Plus size={15}/>{t('background')}</button><Select value={selected} onChange={e => setSelected(e.target.value)} aria-label={t('chooseCompanion')}><option value="">{t('chooseCompanion')}</option>{people.map(p => <option value={p.id} key={p.id}>{p.name}</option>)}</Select></div><Status resource={catalog} t={t}><div className="catalog-grid">{items(catalog.data, 'backgrounds').map(b => <article className="catalog-card" key={b.id}><Media src={b.cover_url} alt={b.title}/><div><span className="eyebrow">{b.genre}</span><h3>{b.title}</h3><p>{b.synopsis}</p><button className="button" disabled={busy} onClick={() => start(b.id)}>{t('startStory')}<ArrowRight size={15}/></button></div></article>)}</div>{!items(catalog.data, 'backgrounds').length && <Empty t={t}/>}</Status>{customBackground && <StoryBackground t={t} close={() => setCustomBackground(false)} done={() => { setCustomBackground(false); catalog.reload(); }} notify={notify}/>}</>;
}
function Pets({ t, notify, refresh }: {
    t: T;
    notify: (e: unknown) => void;
    refresh: () => void;
}) {
    const breeds = useResource('/v1/ai-pets/breeds');
    const [pet, setPet] = useState<Entity | null>(null);
    const state = useResource(pet ? `/v1/ai-pets/${pet.adopted_companion_id}/state` : null, 0, 30000);
    const [adopting, setAdopting] = useState<Entity | null>(null);
    const [petAction, setPetAction] = useState('idle');
    const [careAttempt, setCareAttempt] = useState<Entity | null>(null);
    useEffect(() => {
        try { setCareAttempt(pet ? JSON.parse(sessionStorage.getItem(`vita.pet-care.${pet.adopted_companion_id}`) || 'null') : null); } catch { setCareAttempt(null); }
    }, [pet?.adopted_companion_id]);
    const [busy, setBusy] = useState(false);
    async function care(kind: string) {
        if (!pet || busy) return;
        const storageKey = `vita.pet-care.${pet.adopted_companion_id}`;
        const request = careAttempt || { kind, idempotency_key: crypto.randomUUID() };
        setCareAttempt(request); sessionStorage.setItem(storageKey, JSON.stringify(request));
        setBusy(true);
        try {
            await api(`/v1/ai-pets/${pet.adopted_companion_id}/${request.kind === 'feed' ? 'feed' : 'care'}`, { method: 'POST', body: request });
            setPetAction(`${request.kind}:${Date.now()}`);
            setCareAttempt(null); sessionStorage.removeItem(storageKey);
            state.reload();
            refresh();
        }
        catch (e) {
            if (e instanceof ApiError && e.status < 500 && !['settlement_pending', 'refund_unconfirmed', 'spend_in_progress'].includes(e.code || '')) { setCareAttempt(null); sessionStorage.removeItem(storageKey); }
            notify(e);
        }
        finally {
            setBusy(false);
        }
    }
    if (pet)
        return <><button className="text-button" onClick={() => setPet(null)}><ArrowLeft size={16}/>{t('back')}</button><Status resource={state} t={t}>{state.data && <div className="pet-home"><PetRoom pet={{ ...pet, ...state.data }} action={petAction} t={t} onPet={() => { if (!careAttempt) void care('pet'); }}/><h2>{pet.adopted_companion_name || pet.name}</h2><div className="pet-stats">{(['hunger', 'hydration', 'happiness', 'energy', 'health'] as const).map(key => <label key={key}>{t(key)}<span>{state.data[key]} / 100</span><progress max={100} value={state.data[key]}/></label>)}</div><div className="pet-actions">{(['pet', 'drink', 'walk', 'rest', 'feed'] as const).map(k => <button className={`button ${k === 'feed' ? 'primary' : ''}`} disabled={busy || !!careAttempt} key={k} onClick={() => care(k)}>{t(k)}{k === 'feed' ? ` · ${state.data.feed_coin_cost} ${t('credits')}` : ''}</button>)}</div>{careAttempt && <div className="access-banner"><p>{t('requestUnconfirmed')}</p><button className="button primary" disabled={busy} onClick={() => void care(careAttempt.kind)}>{t('retry')}</button></div>}</div>}</Status></>;
    return <><Status resource={breeds} t={t}><div className="catalog-grid">{items(breeds.data).map(b => <article className="catalog-card pet-catalog" key={b.id}><Media src={b.avatar_url} alt={b.name}/><div><span className="eyebrow">{b.species}</span><h3>{b.name}</h3><p>{b.description}</p><button className="button" disabled={!b.adopted_companion_id && !b.can_adopt} onClick={() => b.adopted_companion_id ? setPet(b) : setAdopting(b)}>{b.adopted_companion_id ? productText('aiPets.openHome', t) : t('adopt')}<ArrowRight size={16}/></button>{!b.adopted_companion_id && !b.can_adopt && <small><a href="#membership">{t('manage')}</a></small>}</div></article>)}</div>{!items(breeds.data).length && <Empty t={t}/>}</Status>{adopting && <Modal title={`${t('adopt')} · ${adopting.name}`} close={() => setAdopting(null)} t={t}><Form t={t} className="form" onSubmit={async (e) => {
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
            }}><label>{t('name')}<Input name="name" required maxLength={40} defaultValue={adopting.name}/></label><button className="button primary" disabled={busy}>{t('adopt')}</button></Form></Modal>}</>;
}
function Account({ t, me, revision, refresh, notify, mode }: {
    mode: 'profile' | 'feedback' | 'membership';
    t: T;
    me: Entity | null;
    revision: number;
    refresh: () => void;
    notify: (e: unknown) => void;
}) {
    const confirm = useConfirm(t);
    const subscription = useResource(mode === 'membership' ? '/v1/me/subscription' : null, revision);
    const credits = useResource(mode === 'membership' ? '/v1/me/credits' : null, revision);
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
    return <div className="account-dialog"><div>{mode === 'profile' && <><section className="account-panel"><h2>{t('profile')}</h2><Form t={t} className="form" onSubmit={e => submit(e, '/v1/me/profile')}><label>{t('nickname')}<Input name="nickname" defaultValue={me?.nickname || ''} maxLength={30}/></label><button className="button" disabled={busy}>{t('save')}</button></Form></section><section className="account-panel"><h2>{t('security')}</h2><Form t={t} className="form" onSubmit={e => submit(e, '/v1/me/password')}><label>{t('currentPassword')}<Input name="current_password" type="password" autoComplete="current-password" required/></label><label>{t('newPassword')}<Input name="new_password" type="password" minLength={6} maxLength={72} autoComplete="new-password" required/></label><button className="button" disabled={busy}>{t('save')}</button></Form></section></>}{mode === 'feedback' && <section className="account-panel"><h2>{t('feedback')}</h2><Form t={t} className="form" onSubmit={e => submit(e, '/v1/feedback', 'POST')}><Textarea name="content" rows={4} placeholder={t('feedbackHint')} required maxLength={2000}/><button className="button" disabled={busy}>{t('send')}</button></Form></section>}</div>{mode === 'membership' && <div><section className="membership-panel"><Sparkles size={25}/><h2>{t('subscription')}</h2><Status resource={subscription} t={t}><p>{t(subscription.data?.is_subscribed ? 'subscribed' : 'notSubscribed')}</p>{subscription.data?.subscription?.current_period_end && <small>{displayDate(subscription.data.subscription.current_period_end, 'date')}</small>}</Status>{subscription.data?.subscription?.provider === 'paypal' && subscription.data.subscription.will_renew && <button className="button" disabled={busy} onClick={async () => {
                if (!(await confirm(t('confirmCancel'))))
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
            }}>{t('cancelRenewal')}</button>}<Billing t={t} notify={notify} refresh={refresh}/></section><section className="account-panel"><span className="eyebrow">{t('credits')}</span><Status resource={credits} t={t}><div className="balance">{credits.data?.balance ?? '—'}<span>{t('credits')}</span></div><h3>{t('transactions')}</h3><div className="transactions">{items(credits.data, 'transactions').map(tx => <div className="transaction" key={tx.id}><span>{tx.description || tx.kind}<small>{displayDate(tx.created_at, 'date')}</small></span><strong>{tx.amount > 0 ? '+' : ''}{tx.amount}</strong></div>)}{!items(credits.data, 'transactions').length && <p className="muted">{t('empty')}</p>}</div></Status></section></div>}{mode === 'profile' && <div><Preferences t={t} notify={notify}/><section className="account-panel"><h2>{t('invitation')}</h2>{me?.invite_code && <div className="invite-code">{me.invite_code}</div>}<Form t={t} className="form" onSubmit={e => submit(e, '/v1/me/invitation', 'POST')}><label>{t('invitationCode')}<Input name="invite_code" required/></label><button className="button" disabled={busy}>{t('bind')}</button></Form></section></div>}</div>;
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
                    window.history.replaceState(null, '', window.location.pathname + '#membership');
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
    const confirm = useConfirm(t);
    const resource = useResource(`/v1/companions/${companion.id}`);
    const [busy, setBusy] = useState(false);
    const [avatar, setAvatar] = useState('');
    const [portraitSelection, setPortraitSelection] = useState<string | null>(null);
    const options = useResource('/v1/companion-options');
    return <Modal title={companion.name} close={close} t={t}><Status resource={resource} t={t}>{resource.data && <Form t={t} className="form" onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                const f = new FormData(e.currentTarget);
                try {
                    await api(`/v1/companions/${companion.id}`, { method: 'PUT', body: { ...resource.data, ...Object.fromEntries(f), portrait_id: f.get('portrait_id') || null, personality_tags: String(f.get('personality_tags') || '').split(/[,，]/).map(tag => tag.trim()).filter(Boolean), ...(avatar ? { avatar_media_id: avatar } : {}) } });
                    notify(new Error(t('saved')));
                    close();
                    changed();
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}><Media src={avatar ? `/v1/media/${avatar}` : portraitSelection ? items(options.data, 'portraits').find(p => p.id === portraitSelection)?.image_url : resource.data.portrait_url} alt={companion.name} className="profile-portrait"/>{(['name', 'persona', 'city', 'occupation', 'interests', 'appearance', 'speaking_style', 'likes', 'dislikes', 'life_habits', 'life_goal', 'backstory'] as const).map(k => <label key={k}>{productText(({ speaking_style: 'companion.create.speakingStyle', life_habits: 'companion.create.lifeHabits', life_goal: 'companion.create.lifeGoal' } as Record<string, string>)[k] || ({ appearance: 'appearance', backstory: 'backstory', interests: 'interests', likes: 'likes', dislikes: 'dislikes' } as Record<string, string>)[k] || k, t)}{['persona', 'backstory', 'likes', 'dislikes', 'life_habits'].includes(k) ? <Textarea name={k} maxLength={4000} defaultValue={resource.data[k]} rows={5}/> : <Input name={k} maxLength={k === 'name' ? 100 : 4000} defaultValue={resource.data[k]} required={k === 'name'}/>}</label>)}<label>{productText('companion.create.traitsEditable', t)}<Input name="personality_tags" defaultValue={(resource.data.personality_tags || []).join(', ')}/></label><label>{t('selectPortrait')}<Select aria-label={t('selectPortrait')} name="portrait_id" value={portraitSelection ?? resource.data.portrait_id ?? ''} onChange={e => { setPortraitSelection(e.target.value); setAvatar(''); }}><option value="" disabled>{t('portrait')}</option>{resource.data.portrait_id && !items(options.data, 'portraits').some(p => p.id === resource.data.portrait_id) && <option value={resource.data.portrait_id}>{t('portrait')}</option>}{items(options.data, 'portraits').filter(p => p.gender !== 'pet').map(p => <option key={p.id} value={p.id}>{p.name || p.id}</option>)}</Select></label><label className="upload-label">{t('upload')}<Input type="file" accept="image/*" disabled={busy} onChange={async e => {
                    const input = e.currentTarget; const file = input.files?.[0]; if (!file) return; setBusy(true);
                    try { const form = new FormData(); form.set('file', file); form.set('kind', 'image'); const uploaded = await api('/v1/companions/image', { method: 'POST', body: form }); setAvatar(uploaded.id); }
                    catch (error) { notify(error); } finally { setBusy(false); input.value = ''; }
                }}/></label><button className="button primary" disabled={busy}>{t('save')}</button>{!resource.data.is_default && <button type="button" className="text-button" disabled={busy} onClick={async () => {
                    if (!(await confirm(t('confirmDelete'))))
                        return;
                    setBusy(true);
                    try {
                        await api(`/v1/companions/${companion.id}`, { method: 'DELETE' });
                        changed(); close();
                    }
                    catch (e) {
                        notify(e);
                        setBusy(false);
                    }
                }}>{t('delete')}</button>}</Form>}</Status></Modal>;
}
function Experiences({ companion, t, close, notify, onMoment }: {
    companion: Entity; t: T; close: () => void; notify: (e: unknown) => void; onMoment: (id: string) => void;
}) {
    const catalog = useResource(`/v1/companions/${companion.id}/experiences`);
    const storageKey = `vita.experience.${companion.id}`;
    const [attempt, setAttempt] = useState<{ product: Entity; body: Entity } | null>(() => {
        try { return JSON.parse(sessionStorage.getItem(storageKey) || 'null'); } catch { return null; }
    });
    const [product, setProduct] = useState<Entity | null>(() => attempt?.product || null);
    const slots = useResource(product?.category === 'date' ? `/v1/companions/${companion.id}/experiences/${product.key}/slots` : null);
    const [busy, setBusy] = useState(false);
    const [result, setResult] = useState<Entity | null>(null);
    const [opened, setOpened] = useState(false);
    const [continueTogether, setContinueTogether] = useState(false);
    async function buy(e: FormEvent<HTMLFormElement>) {
        e.preventDefault();
        if (!product || busy) return;
        const form = new FormData(e.currentTarget);
        const request = attempt || { product, body: { idempotency_key: crypto.randomUUID(), input: { quoted_coins: product.coins, custom_request: form.get('custom_request') || '', ...(form.get('scheduled_at') ? { scheduled_at: form.get('scheduled_at') } : {}) } } };
        setAttempt(request); sessionStorage.setItem(storageKey, JSON.stringify(request)); setBusy(true);
        try {
            const data = await api(`/v1/companions/${companion.id}/experiences/${request.product.key}`, { method: 'POST', body: request.body });
            setResult(data.result); setAttempt(null); sessionStorage.removeItem(storageKey); changed();
        } catch (error) {
            const uncertainCodes = ['spend_in_progress', 'spend_pending', 'settlement_pending', 'refund_unconfirmed', 'date_request_pending'];
            const definiteCodes = ['experience_failed', 'spend_refunded', 'date_decision_failed', 'date_declined', 'date_slots_changed', 'date_schedule_busy', 'invalid_appointment', 'experience_price_changed'];
            const uncertain = error instanceof ApiError ? uncertainCodes.includes(error.code || '') || (error.status >= 500 && !definiteCodes.includes(error.code || '')) : true;
            if (!uncertain) {
                setAttempt(null); sessionStorage.removeItem(storageKey); catalog.reload();
                if (['date_slots_changed', 'date_schedule_busy', 'invalid_appointment'].includes((error as ApiError).code || '')) slots.reload();
                if ((error as ApiError).code === 'experience_price_changed') setProduct(null);
            }
            notify(error);
        } finally { setBusy(false); }
    }
    return <Modal wide={!!result} title={t('experiences')} close={() => { if (!busy) close(); }} t={t}>
        {result ? <div className="experience-result">
            {product?.category === 'gift' && !opened ? <button className="gift-unwrapping" onClick={() => setOpened(true)}><Sparkles size={55}/><span>{productText('experience.flow.openGift', t)}</span></button> : <>
                <div className="experience-delivery"><Media src={result.media_url || result.message?.media_url || companion.portrait_url} kind={result.media_type || result.message?.message_type || result.type} alt={companion.name} className="result-media"/><div><span className="eyebrow">{companion.name}</span><h2>{productText(product?.name_key || 'experiences', t)}</h2><p className="prose">{result.reaction || result.content || (typeof result.message === 'string' ? result.message : result.message?.content) || result.invitation || result.description}</p></div></div>
                {result.event_id ? <button className="button primary" onClick={() => onMoment(result.event_id)}>{t('viewMoment')}<ArrowRight size={16}/></button> : result.spend_id && <button className="button primary" onClick={() => setContinueTogether(true)}>{t('continueChat')}<ArrowRight size={16}/></button>}
                {continueTogether && <div className="moment-chat"><Chat companion={companion} t={t} notify={notify} spendID={result.spend_id}/></div>}
                <button className="text-button" onClick={close}>{t('back')}</button>
            </>}
        </div> : product ? <Form t={t} className="form" onSubmit={buy}>
            <button className="text-button" type="button" disabled={busy || !!attempt} onClick={() => setProduct(null)}><ArrowLeft size={17}/>{t('back')}</button>
            <span className="experience-emoji">{product.emoji}</span><h2>{productText(product.name_key, t)}</h2><p className="muted">{productText(product.description_key, t)}</p>
            {attempt && <p className="access-banner">{t('requestUnconfirmed')}</p>}
            <label>{t('customRequest')}<Textarea name="custom_request" rows={3} maxLength={500} disabled={!!attempt} defaultValue={attempt?.body.input.custom_request || ''}/></label>
            {product.category === 'date' && <Status resource={slots} t={t}><label>{t('appointment')}<Select aria-label={t('appointment')} name="scheduled_at" required disabled={!!attempt} defaultValue={attempt?.body.input.scheduled_at || ''}><option value="">{t('appointment')}</option>{items(slots.data, 'slots').map(slot => <option key={slot.starts_at} value={slot.starts_at}>{displayDate(slot.starts_at)}</option>)}</Select></label>{!slots.loading && !items(slots.data, 'slots').length && <p className="muted">{productText('experience.slots.empty', t)}</p>}<button className="text-button" type="button" disabled={!!attempt || busy} onClick={slots.reload}>{t('retry')}</button></Status>}
            <p>{product.coins} {t('credits')} · {catalog.data?.balance ?? '—'} {t('credits')}</p>
            <button className="button primary" disabled={busy || (!attempt && product.category === 'date' && (slots.loading || !!slots.error || !items(slots.data, 'slots').length))}>{t(busy ? 'loading' : attempt ? 'retry' : 'confirmPurchase')}</button>
        </Form> : <Status resource={catalog} t={t}><p className="muted">{catalog.data?.balance ?? '—'} {t('credits')}</p>{['gift', 'date', 'photo', 'voice', 'outfit', 'keepsake', 'call'].map(category => {
            const products = items(catalog.data, 'products').filter(p => p.is_launched && p.category === category);
            return products.length ? <section className="experience-group" key={category}><h3>{productText(category === 'gift' ? 'experience.flow.group.gift' : category === 'date' ? 'experience.flow.group.date' : 'experience.flow.group.other', t)}</h3><div className="experience-list">{products.map(p => <button className="experience-product" key={p.key} onClick={() => setProduct(p)}><span>{p.emoji}</span><span><strong>{productText(p.name_key, t)}</strong><small>{productText(p.description_key, t)}</small></span><span>{p.coins}<small>{t('credits')}</small></span></button>)}</div></section> : null;
        })}{!items(catalog.data, 'products').some(p => p.is_launched) && <Empty t={t}/>}</Status>}
    </Modal>;
}
function Moment({ companion, eventID, t, notify, close }: {
    companion: Entity; eventID: string; t: T; notify: (e: unknown) => void; close: () => void;
}) {
    const path = `/v1/companions/${companion.id}/moments/${eventID}`;
    const resource = useResource(path, 0, 15000);
    const [busy, setBusy] = useState(false);
    const [now, setNow] = useState(() => Date.now());
    const moment = resource.data;
    useEffect(() => { const timer = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(timer); }, []);
    const upcoming = moment && now < Date.parse(moment.starts_at);
    const ended = moment && now >= Date.parse(moment.ends_at);
    async function action(name: string, body?: Entity, method = 'POST') {
        if (busy) return;
        setBusy(true);
        try { await api(path + '/' + name, { method, body }); changed(); }
        catch (e) { notify(e); } finally { setBusy(false); }
    }
    return <Modal wide title={moment ? productText(moment.title_key, t) : t('appointment')} close={close} t={t}><Status resource={resource} t={t}>{moment && <div className="moment-experience">
        <div className="moment-stage">
            <Media src={moment.scene_image_url || moment.scene_background_url || `/assets/scenes/${moment.location === 'restaurant' ? 'dinner' : ['cafe', 'cinema', 'ballroom'].includes(moment.location) ? moment.location : 'cafe'}.png`} alt={companion.name} className="moment-backdrop"/>
            <div className="moment-scene-copy">{!moment.scene_image_url && <Media src={companion.portrait_url} alt={companion.name} className="moment-companion"/>}<span className="scene-badge">{t(moment.closing ? 'momentFinished' : upcoming ? 'momentUpcoming' : ended ? 'momentEnded' : 'momentActive')}</span><h2>{companion.name}</h2><p>{moment.scene_situation || moment.opening || moment.invitation}</p><small>{displayDate(moment.starts_at)} — {displayDate(moment.ends_at, 'time', { hour: '2-digit', minute: '2-digit' })}</small></div>
        </div>
        <div className="moment-body">
            {moment.scene_audio_url && <details><summary>{t('ambience')}</summary><Media src={moment.scene_audio_url} kind="audio"/></details>}
            {!moment.opening && upcoming && <section className="preparation-panel"><h3>{t('preparation')}</h3><div className="scene-choices">{(['talk', 'quiet', 'story', 'surprise'] as const).map(choice => <button className={`button ${moment.preparation === choice ? 'primary' : ''}`} disabled={busy} key={choice} onClick={() => void action('prepare', { choice })}>{productText('date.prep.' + choice, t)}</button>)}</div><p className="prose">{moment.preparation_reaction}</p><p className="muted">{t('momentWait')}</p></section>}
            {!moment.opening && !upcoming && !ended && <button className="button primary" disabled={busy} onClick={() => void action('start')}>{t('enterDate')}<ArrowRight size={16}/></button>}
            {!moment.opening && ended && <p className="access-banner">{t('momentMissed')}</p>}
            {moment.opening && <>
                <div className="moment-chat"><Chat companion={companion} t={t} notify={notify} eventID={eventID} readOnly={!!ended || !!moment.closing} sceneKind={moment.location || moment.product_key}/></div>
                <section className="keepsake-card"><h3>{t('artifact')}</h3>{!moment.closing && <Form t={t} className="form" onSubmit={e => { e.preventDefault(); void action('artifact', { text: new FormData(e.currentTarget).get('text') }, 'PUT'); }}><label>{t('artifact')}<Textarea name="text" required maxLength={500} rows={3} defaultValue={moment.user_text}/></label><button className="button" disabled={busy}>{t('save')}</button></Form>}<p className="prose">{moment.artifact}</p><p className="prose">{moment.companion_text}</p></section>
                {ended && !moment.closing && <button className="button primary" disabled={busy} onClick={() => void action('finish')}>{t('finish')}<Heart size={17}/></button>}
                {moment.closing && <section className="reaction"><Heart size={22}/><div><p className="prose">{moment.closing}</p><p className="muted">{moment.next_topic}</p></div><a href="#journey" className="button" onClick={close}>{t('journey')}</a></section>}
            </>}
        </div>
    </div>}</Status></Modal>;
}
function Preferences({ t, notify }: {
    t: T;
    notify: (e: unknown) => void;
}) {
    const contact = useResource('/v1/me/contact-preferences');
    const world = useResource('/v1/me/world-preferences');
    const deleted = useResource('/v1/companions-deleted');
    const [busy, setBusy] = useState(false);
    return <><section className="account-panel"><h2>{t('contact')}</h2><Status resource={contact} t={t}>{contact.data && <Form t={t} className="form" onSubmit={async (e) => {
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
            }}>{(['daily_limit', 'minimum_gap_minutes', 'quiet_start', 'quiet_end'] as const).map((key, i) => <label key={key}>{t((['dailyLimit', 'minimumGap', 'quietStart', 'quietEnd'] as const)[i])}<Input type="number" min={i === 1 ? 30 : 0} max={i > 1 ? 23 : i === 0 ? 8 : 1440} name={key} required defaultValue={contact.data.preferences[key]}/></label>)}<label className="checkbox"><Input type="checkbox" name="quiet_enabled" defaultChecked={contact.data.preferences.quiet_enabled}/>{t('quiet')}</label><button className="button" disabled={busy}>{t('save')}</button></Form>}</Status></section><section className="account-panel"><h2>{t('world')}</h2><Status resource={world} t={t}>{world.data && <Form t={t} className="form" onSubmit={async (e) => {
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
            }}><label>{t('timezone')}<Input name="timezone" defaultValue={world.data.timezone} required/></label><label>{t('region')}<Input name="region_code" defaultValue={world.data.region_code} required maxLength={6}/></label><button className="button" disabled={busy}>{t('save')}</button></Form>}</Status></section><Status resource={deleted} t={t}>{items(deleted.data).length > 0 && <section className="account-panel"><h2>{t('deletedCompanions')}</h2>{items(deleted.data).map(c => <div className="transaction" key={c.id}><span>{c.name}</span><button className="button" disabled={busy} onClick={async () => {
                    setBusy(true);
                    try {
                        await api(`/v1/companions/${c.id}/restore`, { method: 'POST' });
                        changed(); close();
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
    return <div className="workspace-start"><div className="start-center"><h1>{t('startTitle')}</h1><Form t={t} className="start-composer" onSubmit={begin}><button type="button" className="icon-button" onClick={login} aria-label={t('attachment')}><Plus size={23} strokeWidth={1.5}/></button><Input value={draft} onChange={e => setDraft(e.target.value)} placeholder={t('startPlaceholder')} aria-label={t('message')}/><div className="start-composer-tools"><span>Vita</span><button className="start-send" aria-label={t('send')}><ArrowUp size={20}/></button></div></Form><div className="start-suggestions"><button onClick={login}><MessageCircle size={18}/><span>{t('startSuggestionChat')}</span></button><button onClick={() => navigate('stories')}><BookOpen size={18}/><span>{t('startSuggestionStory')}</span></button><button onClick={() => navigate('pets')}><PawPrint size={18}/><span>{t('startSuggestionPet')}</span></button></div></div></div>;
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
    const options = useResource('/v1/companion-options');
    const [role, setRole] = useState('');
    return <Modal title={t('generateCompanion')} close={close} t={t}><button className="text-button" onClick={back}><ArrowLeft size={16}/>{t('manual')}</button>{!draft ? <Form t={t} className="form" onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                const f = new FormData(e.currentTarget);
                if (!(f.get('document') as File)?.size && !String(f.get('description') || '').trim()) { setBusy(false); notify(new Error(t('descriptionRequired'))); return; }
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
            }}><label>{t('name')}<Input name="character_name" required maxLength={100}/></label><label>{t('description')}<Textarea name="description" rows={5} maxLength={4000}/></label><label>{t('document')}<Input name="document" type="file" accept=".pdf,.docx,.txt"/></label><label>{t('upload')}<Input name="image" type="file" accept="image/*" required/></label><button className="button primary" disabled={busy}>{busy ? t('loading') : t('generate')}</button></Form> : <Form t={t} className="form" onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                try {
                    const result = await api('/v1/companions/', { method: 'POST', body: { ...draft.profile, ...Object.fromEntries(new FormData(e.currentTarget)), personality_tags: String(new FormData(e.currentTarget).get('personality_tags') || '').split(/[,，]/).map(tag => tag.trim()).filter(Boolean), avatar_media_id: draft.avatar_media_id, creation_source: draft.creation_source } });
                    done(result.id);
                }
                catch (e) {
                    notify(e);
                }
                finally {
                    setBusy(false);
                }
            }}><Media src={draft.portrait_url} className="profile-portrait" alt={draft.profile.name}/><label>{t('name')}<Input name="name" defaultValue={draft.profile.name} required/></label><label>{t('persona')}<Textarea name="persona" rows={7} defaultValue={draft.profile.persona}/></label>{(['city', 'occupation', 'interests', 'appearance', 'speaking_style', 'likes', 'dislikes', 'life_habits', 'life_goal', 'backstory'] as const).map(key => <label key={key}>{productText(({ speaking_style: 'companion.create.speakingStyle', life_habits: 'companion.create.lifeHabits', life_goal: 'companion.create.lifeGoal' } as Record<string, string>)[key] || key, t)}<Textarea name={key} rows={2} maxLength={4000} defaultValue={draft.profile[key] || ''}/></label>)}<label>{productText('companion.create.traitsEditable', t)}<Input name="personality_tags" defaultValue={(draft.profile.personality_tags || []).join(', ')}/></label><label>{t('relationship')}<Select aria-label={t('relationship')} name="gender" value={role || draft.profile.gender || 'custom'} onChange={e => setRole(e.target.value)}>{items(options.data, 'relationships').map(option => <option key={option.key} value={option.key}>{productText(`relation.${option.key}`, t)}</option>)}</Select></label><label>{t('closeness')}<Select aria-label={t('closeness')} name="relationship_stage" key={role} defaultValue={role ? items(options.data, 'relationships').find(option => option.key === role)?.default_stage : draft.profile.relationship_stage}>{(items(options.data, 'relationships').find(option => option.key === (role || draft.profile.gender || 'custom'))?.stages || []).map((stage: string) => <option key={stage} value={stage}>{productText(`stage.${stage}`, t)}</option>)}</Select></label><button className="button primary" disabled={busy || options.loading || !!options.error}>{t('newCompanion')}</button></Form>}</Modal>;
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
    return <Modal title={t('background')} close={close} t={t}><Form t={t} className="form" onSubmit={async (e) => {
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
        }}>{([{ key: 'title', label: 'name' }, { key: 'synopsis', label: 'synopsis' }, { key: 'world_setting', label: 'worldSetting' }, { key: 'opening', label: 'opening' }, { key: 'genre', label: 'genre' }, { key: 'story_goal', label: 'storyGoal' }] as const).map(field => <label key={field.key}>{t(field.label)}<Textarea name={field.key} required maxLength={field.key === 'title' ? 80 : 4000} rows={field.key === 'title' || field.key === 'genre' ? 1 : 3}/></label>)}<button className="button primary" disabled={busy}>{t('save')}</button></Form></Modal>;
}
function StoryBoardAction({ story, t, notify, changed }: {
    story: Entity;
    t: T;
    notify: (e: unknown) => void;
    changed: () => Promise<void>;
}) {
    const confirm = useConfirm(t);
    const [busy, setBusy] = useState(false);
    const requestKey = useRef<string | null>(null);
    const [panelCount, setPanelCount] = useState(4);
    if (!story.storyboard_unlocked)
        return null;
    return <div className="form"><p className="muted">{story.config?.storyboard_coins} {t('credits')}</p><Select value={panelCount} aria-label={t('storyboard')} onChange={e => setPanelCount(Number(e.target.value))} disabled={!!requestKey.current}><option value={4}>4</option><option value={6}>6</option><option value={9}>9</option></Select><button className="button" disabled={busy} onClick={async () => {
            if (!requestKey.current && !(await confirm(`${t('storyboard')} · ${story.config?.storyboard_coins} ${t('credits')}?`)))
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
