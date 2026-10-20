'use client';
import { useEffect, useRef, useState } from 'react';
import { Moon, Sun } from 'lucide-react';
import { Media, useMediaURL } from './companion-ui';
import type { Entity } from '../lib/api';
import type { MessageKey } from '../lib/i18n';

type Props = { pet: Entity; action: string; t: (key: MessageKey) => string; onPet: () => void };
export default function PetRoom({ pet, action, t, onPet }: Props) {
    const canvas = useRef<HTMLCanvasElement>(null);
    const poses = useMediaURL(pet.sprite_sheet_url);
    const actions = useMediaURL(pet.action_sheet_url);
    const [ready, setReady] = useState(false);
    const [current, setCurrent] = useState(action);
    const [night, setNight] = useState(false);
    useEffect(() => {
        setCurrent(action.split(':')[0]);
        const timer = setTimeout(() => setCurrent('idle'), 6000);
        return () => clearTimeout(timer);
    }, [action]);
    useEffect(() => {
        let active = true;
        let timer: ReturnType<typeof setInterval> | undefined;
        const sheet = new Image();
        const actionSheet = new Image();
        let tick = 0;
        const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        const draw = () => {
            if (!active || document.hidden) return;
            const context = canvas.current?.getContext('2d');
            if (!context) return;
            const resting = current === 'rest' || night;
            const index = resting ? 5 : current === 'feed' ? 3 : current === 'drink' ? 4 : current === 'walk' ? 2 : current === 'pet' ? 1 : Math.floor(tick / 14) % 2;
            const animated = !reduced && !resting && ['feed', 'drink', 'walk'].includes(current) && actionSheet.complete && actionSheet.naturalWidth > 0 && Math.abs(actionSheet.naturalWidth / actionSheet.naturalHeight - 1.5) < .02;
            let source = sheet;
            let frame = index;
            if (animated) {
                if (current === 'walk') { source = actionSheet; frame = [0, 1, 2, 1][tick % 4]; }
                else if (current === 'feed') { source = actionSheet; frame = [3, 4, 4, 3][tick % 4]; }
                else if (tick % 3) { source = actionSheet; frame = 5; }
            }
            const width = source.naturalWidth / 3, height = source.naturalHeight / 2;
            const inset = frame >= 3 ? height * (source === actionSheet ? .02 : .06) : 0;
            const ragdoll = source === sheet && poses.includes('cat_ragdoll') && frame === 1;
            const left = ragdoll ? width * .035 : 0;
            const overflow = frame < 3 && !ragdoll ? height * (source === actionSheet ? .02 : .06) : 0;
            context.clearRect(0, 0, 360, 360);
            context.drawImage(source, (frame % 3) * width + left, Math.floor(frame / 3) * height + inset, width - left, height - inset + overflow, 0, 0, 360, 360);
            tick++;
        };
        setReady(false);
        sheet.onload = () => {
            if (!active || Math.abs(sheet.naturalWidth / sheet.naturalHeight - 1.5) >= .02) return;
            setReady(true); draw(); timer = setInterval(draw, reduced ? 6000 : 300);
        };
        if (actions) actionSheet.src = actions;
        if (poses) sheet.src = poses;
        return () => { active = false; sheet.onload = null; clearInterval(timer); };
    }, [poses, actions, current, night]);
    return <div className={`pet-room ${night ? 'pet-room-night' : ''}`}>
        <div className="pet-window"><span/><span/><span/><span/></div><div className="pet-rug"/><div className="pet-bowl"/><div className="pet-room-title"><span>{pet.adopted_companion_name || pet.name}</span><button className="icon-button" onClick={() => setNight(value => !value)} aria-label={t(night ? 'light' : 'dark')}>{night ? <Moon size={20}/> : <Sun size={20}/>}</button></div>
        <button className={`pet-character pet-motion-${current}`} onClick={onPet} aria-label={t('pet')}><canvas ref={canvas} width={360} height={360} hidden={!ready}/>{!ready && <Media src={pet.avatar_url} alt={pet.name}/>}</button>
        <div className="pet-speech" role="status">{t(current === 'idle' ? 'petWelcome' : current === 'feed' ? 'petEating' : current === 'drink' ? 'petDrinking' : current === 'walk' ? 'petWalking' : current === 'rest' ? 'petResting' : 'petHappy')}</div>
    </div>;
}
