'use client';
import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, Gift, Heart, MessageCircle, Plus, Settings2, Share2 } from 'lucide-react';
import { api, ApiError, baseURL, items, type Entity } from '../lib/api';
import { useResource } from '../lib/companion-data';
import { productText, type MessageKey } from '../lib/i18n';
import { Media, Modal } from './companion-ui';
import Select from './select';
import Skeleton from './skeleton';
import { Form, Input, Textarea } from './form';
type T = (key: MessageKey) => string;
type Props = { t: T; notify: (error: unknown) => void; changed: () => void };
export default function Encounters({ t, notify, changed }: Props) {
    const characters = useResource('/v1/encounters/characters');
    const preferences = useResource('/v1/encounters/preferences');
    const conversations = useResource('/v1/encounters/conversations', 0, 12000);
    const [tab, setTab] = useState('browse');
    const [index, setIndex] = useState(0);
    const [form, setForm] = useState('');
    const [profile, setProfile] = useState<Entity | null>(null);
    const [chat, setChat] = useState<Entity | null>(null);
    const [busy, setBusy] = useState(false);
    const pointer = useRef<number | null>(null);
    const swiped = useRef(false);
    const list = items(characters.data);
    const current = list[index % Math.max(1, list.length)];
    const step = (direction: number) => setIndex(value => (value + direction + list.length) % Math.max(1, list.length));
    async function open(character: Entity) {
        if (busy) return;
        setBusy(true);
        try { const result = await api('/v1/encounters/conversations', { method: 'POST', body: { character_id: character.id } }); setChat({ ...character, conversation_id: result.id }); }
        catch (error) { notify(error); } finally { setBusy(false); }
    }
    const reload = () => { characters.reload(); conversations.reload(); changed(); };
    if (chat) return <><EncounterChat key={chat.conversation_id} character={chat} t={t} notify={notify} changed={changed} back={() => { setChat(null); reload(); }} onProfile={() => setProfile(chat)}/>{profile && <EncounterProfile character={profile} t={t} notify={notify} close={() => setProfile(null)} onChat={() => setProfile(null)}/>}</>;
    return <section className="encounters">
        <header className="section-toolbar"><div><span className="eyebrow">{t('explore')}</span><h1>{t('encounters')}</h1><p className="muted">{t('encountersIntro')}</p></div><button className="icon-button" aria-label={t('encounter.preferences')} onClick={() => setForm('preferences')}><Settings2 size={21}/></button></header>
        {characters.loading || preferences.loading ? <Skeleton t={t} variant="world"/> : characters.error || preferences.error ? <div className="state" role="alert"><p>{characters.error || preferences.error}</p><button className="button" onClick={() => { characters.reload(); preferences.reload(); }}>{t('retry')}</button></div> : !preferences.data?.configured ? <div className="encounter-welcome"><Heart size={40}/><h2>{t('encounter.welcome')}</h2><button className="button primary" onClick={() => setForm('preferences')}>{t('encounter.preferences')}</button></div> : tab === 'browse' ? current ? <>
            <div className="encounter-deck" tabIndex={0} role="region" aria-label={t('encounters')} onKeyDown={e => { if (e.target !== e.currentTarget) return; if (e.key === 'ArrowRight') { e.preventDefault(); step(1); } if (e.key === 'ArrowLeft') { e.preventDefault(); step(-1); } }} onClickCapture={e => { if (swiped.current) { e.preventDefault(); e.stopPropagation(); swiped.current = false; } }} onPointerDown={e => { pointer.current = e.clientX; swiped.current = false; }} onPointerUp={e => { if (pointer.current !== null && Math.abs(e.clientX - pointer.current) > 70) { swiped.current = true; step(e.clientX < pointer.current ? 1 : -1); } pointer.current = null; }} onPointerCancel={() => { pointer.current = null; }}>
                {Array.from({ length: Math.min(6, list.length) }, (_, depth) => {
                    const person = list[(index + depth) % list.length];
                    return <article key={`${person.id}:${depth}`} className="encounter-card" style={{ zIndex: 6 - depth, transform: `translateY(${depth * 11}px) scale(${1 - depth * .035}) rotate(${depth % 2 ? 1 : -1}deg)` }} aria-hidden={depth > 0} inert={depth > 0}>
                        <Media src={person.cover_url} alt={person.name}/><div className="encounter-card-copy"><button className="text-button" onClick={() => setProfile(person)}><h2>{person.name} · {person.age}</h2></button><p className="encounter-traits">{person.personality}</p><p className="encounter-tags">{(person.tags || []).join(' · ')}</p><small>{t('encounter.followers').replace('@count', String(person.follower_count || 0))}</small><p className="encounter-description">{person.description}</p><button className="button primary" disabled={busy} onClick={() => void open(person)}>{t('startChat')}<MessageCircle size={18}/></button></div>
                    </article>;
                })}
            </div><div className="deck-controls"><button className="icon-button" aria-label={t('previous')} onClick={() => step(-1)}><ArrowLeft size={22}/></button><button className="button" onClick={() => setProfile(current)}>{t('details')}</button><button className="icon-button" aria-label={t('next')} onClick={() => step(1)}><ArrowRight size={22}/></button></div>
        </> : <div className="state"><p>{t('encounter.empty')}</p><button className="button" onClick={() => setForm('preferences')}>{t('encounter.preferences')}</button></div> : <div className="encounter-conversations">{conversations.loading && conversations.data == null && <Skeleton t={t} variant="people"/>}{conversations.error && <p role="alert">{conversations.error}<button className="button" onClick={conversations.reload}>{t('retry')}</button></p>}{items(conversations.data).map(c => <button className="person-link" key={c.id} onClick={() => setChat({ ...c, id: c.character_id, conversation_id: c.id })}><Media src={c.avatar_url || c.cover_url} className="avatar" alt={c.name}/><span>{c.name}<small>{c.last_message}</small></span>{c.unread_count > 0 && <i className="unread">{c.unread_count}</i>}</button>)}{!conversations.loading && !items(conversations.data).length && <p className="state">{t('chatEmpty')}</p>}</div>}
        <nav className="encounter-dock" aria-label={t('encounters')}><button className={`button ${tab === 'browse' ? 'primary' : ''}`} onClick={() => setTab('browse')}><Heart size={18}/>{t('encounter.explore')}</button><button className="button" onClick={() => setForm(preferences.data?.configured ? 'create' : 'preferences')}><Plus size={18}/>{t('encounter.create')}</button><button className={`button ${tab === 'conversations' ? 'primary' : ''}`} onClick={() => setTab('conversations')}><MessageCircle size={18}/>{t('chat')}</button></nav>
        {form && <EncounterForm key={form} preferences={form === 'preferences'} initial={preferences.data} t={t} notify={notify} close={() => setForm('')} done={created => { setForm(''); preferences.reload(); reload(); setIndex(0); if (created) void open(created); }}/>}
        {profile && <EncounterProfile character={profile} t={t} notify={notify} close={() => { setProfile(null); reload(); }} onChat={person => { setProfile(null); void open(person); }}/>} 
    </section>;
}
function EncounterForm({ preferences, initial, t, notify, close, done }: { preferences: boolean; initial: Entity | null; t: T; notify: (error: unknown) => void; close: () => void; done: (character?: Entity) => void }) {
    const [images, setImages] = useState<string[]>([]);
    const [avatar, setAvatar] = useState('');
    const [busy, setBusy] = useState(false);
    async function upload(input: HTMLInputElement, portrait = false) {
        const file = input.files?.[0]; if (!file) return;
        setBusy(true);
        try { const form = new FormData(); form.set('file', file); form.set('kind', 'image'); const result = await api('/v1/companions/image', { method: 'POST', body: form }); const url = `/v1/media/${result.id}`; if (portrait) setAvatar(url); else setImages(old => [...old, url].slice(0, 3)); }
        catch (error) { notify(error); } finally { setBusy(false); input.value = ''; }
    }
    return <Modal title={t(preferences ? 'encounter.preferences' : 'encounter.create')} close={close} t={t}><Form t={t} className="form" onSubmit={async e => {
        e.preventDefault(); if (busy) return;
        const data = Object.fromEntries(new FormData(e.currentTarget));
        setBusy(true);
        try {
            const result = await api(preferences ? '/v1/encounters/preferences' : '/v1/encounters/characters', { method: preferences ? 'PUT' : 'POST', body: preferences ? data : { ...data, age: Number(data.age), tags: String(data.tags).split(/[,，]/).map(s => s.trim()).filter(Boolean), image_urls: images, cover_url: images[0], avatar_url: avatar, enabled: true } });
            done(preferences ? undefined : result);
        } catch (error) { notify(error); } finally { setBusy(false); }
    }}>
        {!preferences && <label>{t('name')}<Input name="name" required maxLength={80}/></label>}
        <label>{t('encounter.gender')}<Select aria-label={t('encounter.gender')} name="gender" defaultValue={initial?.gender || (preferences ? '' : 'female')}>{preferences && <option value="">{t('encounter.any')}</option>}{['male', 'female', 'other'].map(key => <option key={key} value={key}>{productText(`encounter.${key}`, t)}</option>)}</Select></label>
        <label>{t('encounter.personality')}<Input name="personality" maxLength={200} defaultValue={initial?.personality || ''}/></label>
        {!preferences && <>
            <label>{t('encounter.age')}<Input type="number" name="age" min={18} max={100} required defaultValue={25}/></label>
            <label>{t('encounter.tags')}<Input name="tags" maxLength={240}/></label>
            <label>{t('encounter.persona')}<Textarea name="persona" maxLength={4000} rows={4}/></label>
            <label>{t('description')}<Textarea name="description" maxLength={500} rows={3}/></label>
            <p className="muted">{t('encounter.imagesHint')}</p><div className="portrait-picker">{images.map((url, i) => <button key={url} type="button" onClick={() => setImages(old => old.filter((_, n) => n !== i))} disabled={busy} aria-label={t('encounter.removeImage')}><Media src={url} alt={t('portrait')}/></button>)}</div>
            <label className="upload-label">{t('encounter.cover')}<Input type="file" accept="image/*" disabled={busy || images.length >= 3} onChange={e => void upload(e.currentTarget)}/></label>
            {avatar && <Media src={avatar} className="avatar" alt={t('portrait')}/>}<label className="upload-label">{t('encounter.avatar')}<Input type="file" accept="image/*" disabled={busy} onChange={e => void upload(e.currentTarget, true)}/></label>
        </>}
        <button className="button primary" disabled={busy || (!preferences && !images.length)}>{t(busy ? 'loading' : 'save')}</button>
    </Form></Modal>;
}
function EncounterProfile({ character, t, notify, close, onChat }: { character: Entity; t: T; notify: (error: unknown) => void; close: () => void; onChat: (person: Entity) => void }) {
    const resource = useResource(`/v1/encounters/characters/${character.id}`);
    const person = resource.data || character;
    const [image, setImage] = useState(0);
    const [busy, setBusy] = useState(false);
    const [report, setReport] = useState(false);
    const attempt = useRef<Entity | null>(null);
    return <Modal wide title={person.name} close={close} t={t}>
        {resource.error && <p role="alert">{resource.error}<button className="button" onClick={resource.reload}>{t('retry')}</button></p>}
        <div className="encounter-profile"><div><Media src={person.image_urls?.[image] || person.cover_url} className="encounter-profile-cover" alt={person.name}/><div className="scene-choices">{(person.image_urls || []).map((url: string, i: number) => <button className="portrait-thumbnail" key={url} aria-label={t('encounter.imageNumber').replace('@number', String(i + 1))} onClick={() => setImage(i)}><Media src={url} alt={person.name}/></button>)}</div></div><div><h2>{person.name} · {person.age}</h2><p>{person.personality}</p><p>{(person.tags || []).join(' · ')}</p><p className="prose">{person.description}</p><p className="muted">{t('encounter.followers').replace('@count', String(person.follower_count || 0))}</p><div className="scene-choices"><button className="button" disabled={busy || person.enabled === false} onClick={async () => { setBusy(true); try { await api(`/v1/encounters/characters/${person.id}/follow`, { method: 'PUT', body: { following: !person.is_following } }); resource.reload(); } catch (error) { notify(error); } finally { setBusy(false); } }}><Heart size={17}/>{t(person.is_following ? 'encounter.unfollow' : 'encounter.follow')}</button>
        <button className="button" disabled={busy || person.enabled === false} onClick={async () => {
            setBusy(true);
            try { const text = `${person.name} · ${person.age}\n${(person.tags || []).join(' · ')}\n${person.description || ''}`; const url = person.is_private ? undefined : new URL(`${baseURL}/v1/encounters/share/${person.id}`, window.location.origin).href; if (navigator.share) await navigator.share({ title: person.name, text, ...(url ? { url } : {}) }); else { await navigator.clipboard.writeText([text, url].filter(Boolean).join('\n')); notify(new Error(t('copied'))); } }
            catch (error) { if (!(error instanceof DOMException && error.name === 'AbortError')) notify(error); } finally { setBusy(false); }
        }}><Share2 size={17}/>{t('encounter.share')}</button></div><button className="button primary" disabled={person.enabled === false} onClick={() => onChat(person)}>{t('startChat')}</button><button className="text-button" onClick={() => setReport(value => !value)}>{t('encounter.report')}</button></div></div>
        {report && <Form t={t} className="form report-form" onSubmit={async e => {
            e.preventDefault(); if (!attempt.current) attempt.current = { ...Object.fromEntries(new FormData(e.currentTarget)), idempotency_key: crypto.randomUUID() }; setBusy(true);
            try { await api(`/v1/encounters/characters/${person.id}/reports`, { method: 'POST', body: attempt.current }); notify(new Error(t('encounter.reportReceived'))); close(); }
            catch (error) { notify(error); } finally { setBusy(false); }
        }}><label>{t('encounter.report')}<Select aria-label={t('encounter.report')} name="reason" disabled={!!attempt.current}>{['inappropriate', 'harassment', 'misleading', 'other'].map(reason => <option key={reason} value={reason}>{productText(`encounter.reason_${reason}`, t)}</option>)}</Select></label><label>{t('encounter.reportDetails')}<Textarea name="details" required minLength={10} maxLength={2000} rows={4} readOnly={!!attempt.current}/></label><label>{t('encounter.contact')}<Input name="contact" maxLength={200} readOnly={!!attempt.current}/></label><button className="button primary" disabled={busy}>{t('encounter.submitReport')}</button></Form>}
    </Modal>;
}
function EncounterChat({ character, t, notify, changed, back, onProfile }: Props & { character: Entity; back: () => void; onProfile: () => void }) {
    const path = `/v1/encounters/conversations/${character.conversation_id}`;
    const messages = useResource(path + '/messages', 0, 5000);
    const catalog = useResource('/v1/encounters/catalog');
    const [text, setText] = useState('');
    const [busy, setBusy] = useState(false);
    const [product, setProduct] = useState<Entity | null>(null);
    const [products, setProducts] = useState(false);
    const [attempt, setAttempt] = useState<Entity | null>(() => {
        try { return JSON.parse(sessionStorage.getItem(`vita.encounter.${character.conversation_id}`) || 'null'); } catch { return null; }
    });
    const viewport = useRef<HTMLDivElement>(null);
    const follow = useRef(true);
    const read = useRef('');
    const [atBottom, setAtBottom] = useState(true);
    const [visible, setVisible] = useState(true);
    const last = items(messages.data).filter(m => m.sender_type === 'assistant').at(-1);
    useEffect(() => { const update = () => setVisible(!document.hidden); update(); document.addEventListener('visibilitychange', update); return () => document.removeEventListener('visibilitychange', update); }, []);
    useEffect(() => { if (follow.current && viewport.current) viewport.current.scrollTop = viewport.current.scrollHeight; }, [messages.data]);
    useEffect(() => {
        const dialogs = document.querySelectorAll<HTMLDialogElement>('dialog[open]');
        const top = dialogs.item(dialogs.length - 1);
        if (!last || !visible || !atBottom || last.id === read.current || (top && viewport.current && !top.contains(viewport.current))) return;
        let active = true;
        api(path + '/read', { method: 'PUT', body: { message_id: last.id } }).then(() => { if (active) { read.current = last.id; changed(); } }).catch(() => {});
        return () => { active = false; };
    }, [last?.id, messages.data, visible, atBottom, path, changed]);
    const processing = messages.data?.processing_request;
    async function send(body: Entity) {
        if (busy) return;
        setBusy(true); setAttempt(body); sessionStorage.setItem(`vita.encounter.${character.conversation_id}`, JSON.stringify(body));
        try {
            await api(path + '/messages', { method: 'POST', body });
            setAttempt(null); sessionStorage.removeItem(`vita.encounter.${character.conversation_id}`); setText(''); setProduct(null); setProducts(false); follow.current = true; messages.reload(); changed();
        } catch (error) {
            if (error instanceof ApiError && error.status < 500 && !['request_processing', 'settlement_pending'].includes(error.code || '')) { setAttempt(null); sessionStorage.removeItem(`vita.encounter.${character.conversation_id}`); if (error.code === 'price_changed') { setProduct(null); catalog.reload(); } }
            notify(error);
        } finally { setBusy(false); }
    }
    return <div className="encounter-chat"><header className="conversation-head"><button className="icon-button" onClick={back} aria-label={t('back')}><ArrowLeft size={21}/></button><button className="text-button" onClick={onProfile}><Media src={character.avatar_url || character.cover_url} className="avatar" alt={character.name}/><h2>{character.name}</h2></button><span className="conversation-meta">{busy || processing ? t('replying') : t('encounters')}</span></header>
        <div className="encounter-chat-scene"><Media src={character.cover_url} className="encounter-chat-backdrop" alt=""/><div className="messages" ref={viewport} onScroll={e => { const el = e.currentTarget; follow.current = el.scrollHeight - el.scrollTop - el.clientHeight < 60; setAtBottom(follow.current); }}>
            {messages.loading && messages.data == null && <Skeleton t={t} variant="chat"/>}{messages.error && <div className="inline-error" role="alert">{messages.error}<button className="button" onClick={messages.reload}>{t('retry')}</button></div>}
            {items(messages.data).map(m => <article className={`message ${m.sender_type === 'user' ? 'user-message' : 'companion-message'}`} key={m.id}>{m.content && <p>{m.content}</p>}{m.media_url && <Media src={m.media_url} kind={m.media_type} className="message-media" alt={character.name}/>}</article>)}
            {(processing || busy) && <div className="replying"><span className="spinner"/>{t('replying')}</div>}
        </div></div>
        {attempt && !busy && <div className="access-banner"><span>{t('requestUnconfirmed')}</span><button className="button" onClick={() => void send(attempt)}>{t('encounter.retry')}</button></div>}
        <Form t={t} className="composer" onSubmit={e => { e.preventDefault(); if (text.trim()) void send({ content: text.trim(), idempotency_key: crypto.randomUUID() }); }}><Textarea aria-label={t('message')} placeholder={t('message')} maxLength={2000} value={text} onChange={e => setText(e.target.value)} disabled={busy || !!attempt || !!processing}/><div className="composer-bottom"><button className="icon-button" type="button" aria-label={t('experiences')} disabled={busy || !!attempt || !!processing} onClick={() => { catalog.reload(); setProducts(true); }}><Gift size={21}/></button><button className="button primary" disabled={busy || !!attempt || !!processing || !text.trim()}>{t('send')}</button></div></Form>
        {products && <Modal title={t('experiences')} close={() => { if (!busy) { setProducts(false); setProduct(null); } }} t={t}>{catalog.loading && catalog.data == null ? <Skeleton t={t}/> : catalog.error ? <p role="alert">{catalog.error}<button className="button" onClick={catalog.reload}>{t('retry')}</button></p> : product ? <Form t={t} className="form" onSubmit={e => { e.preventDefault(); if (attempt) { void send(attempt); return; } const content = String(new FormData(e.currentTarget).get('content') || '').trim(); void send({ content, idempotency_key: crypto.randomUUID(), product_key: product.key, quoted_coins: product.coins }); }}><h3>{productText(product.name_key, t)}</h3><p>{productText(product.description_key, t)}</p><label>{t('encounter.demand')}<Textarea name="content" required maxLength={2000} rows={4} defaultValue={product.category === 'gift' ? t('encounter.giftMessage').replace('@gift', productText(product.name_key, t)) : ''} readOnly={!!attempt}/></label><p>{product.coins} {t('credits')}</p><p className="muted">{t('encounter.refund')}</p><button className="button primary" disabled={busy || !!processing}>{t(attempt ? 'encounter.retry' : 'confirmPurchase')}</button></Form> : <><p className="muted">{catalog.data?.balance ?? '—'} {t('credits')}</p>{catalog.data?.is_subscribed === false && <a className="button" href="#account" onClick={() => setProducts(false)}>{t('manage')}</a>}<div className="experience-list">{items(catalog.data, 'products').map(p => <button className="experience-product" key={p.key} disabled={catalog.data?.is_subscribed === false} onClick={() => setProduct(p)}><span>{p.emoji}</span><span><strong>{productText(p.name_key, t)}</strong><small>{productText(p.description_key, t)}</small></span><span>{p.coins} {t('credits')}</span></button>)}</div>{!catalog.loading && !items(catalog.data, 'products').length && <p className="state">{t('encounter.unavailable')}</p>}</>}</Modal>}
    </div>;
}
