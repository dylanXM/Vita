'use client';
import { Children, isValidElement, useEffect, useId, useRef, useState, type ReactNode, type SelectHTMLAttributes } from 'react';
import { Check, ChevronDown } from 'lucide-react';
import { FieldError, useFieldError } from './form';

type Props = Omit<SelectHTMLAttributes<HTMLSelectElement>, 'multiple' | 'size' | 'value' | 'defaultValue'> & {
    value?: string | number;
    defaultValue?: string | number;
};
type Option = { value: string; label: ReactNode; disabled: boolean };

export default function Select({ children, value, defaultValue, className = '', onChange, disabled, id, required, onInvalid, ...props }: Props) {
    const options = Children.toArray(children).filter(isValidElement).map(element => {
        const option = element.props as { value?: string | number; children?: ReactNode; disabled?: boolean };
        return { value: String(option.value ?? option.children ?? ''), label: option.children, disabled: !!option.disabled };
    });
    const [internal, setInternal] = useState(String(defaultValue ?? ''));
    const [open, setOpen] = useState(false);
    const [active, setActive] = useState(0);
    const [invalid, setInvalid] = useState(false);
    const trigger = useRef<HTMLButtonElement>(null);
    const native = useRef<HTMLSelectElement>(null);
    const menu = useRef<HTMLSpanElement>(null);
    const search = useRef({ text: '', at: 0 });
    const generatedID = useId();
    const triggerID = id || generatedID;
    const menuID = `${triggerID}-options`;
    const fieldID = `${triggerID}-native`;
    const error = useFieldError(fieldID);
    const raw = String(value ?? internal);
    const selected = options.find(option => option.value === raw) || options[0];
    const selectedValue = selected?.value || '';
    const selectedIndex = Math.max(0, options.findIndex(option => option.value === selectedValue));

    function choose(option: Option) {
        if (disabled || option.disabled || !native.current) return;
        native.current.value = option.value;
        native.current.dispatchEvent(new Event('change', { bubbles: true }));
        setInvalid(false);
        setOpen(false);
        trigger.current?.focus();
    }
    function move(direction: number) {
        let next = open ? active : selectedIndex;
        for (let i = 0; i < options.length; i++) {
            next = (next + direction + options.length) % options.length;
            if (!options[next].disabled) { setActive(next); break; }
        }
        setOpen(true);
    }
    useEffect(() => {
        if (disabled) { setOpen(false); return; }
        if (!open) return;
        const panel = menu.current;
        const button = trigger.current;
        if (!panel || !button) return;
        const position = () => {
            const rect = button.getBoundingClientRect();
            const width = Math.min(Math.max(rect.width, 200), window.innerWidth - 24);
            const below = window.innerHeight - rect.bottom - 16;
            const above = rect.top - 16;
            const upward = below < 180 && above > below;
            panel.style.width = `${width}px`;
            panel.style.maxHeight = `${Math.max(44, Math.min(320, upward ? above : below))}px`;
            const rtl = document.documentElement.dir === 'rtl';
            panel.style.left = `${Math.max(12, Math.min(rtl ? rect.right - width : rect.left, window.innerWidth - width - 12))}px`;
            panel.style.top = `${upward ? Math.max(12, rect.top - panel.offsetHeight - 8) : rect.bottom + 8}px`;
        };
        panel.showPopover();
        position();
        const outside = (event: PointerEvent) => {
            if (event.target instanceof Node && !panel.contains(event.target) && !button.contains(event.target)) setOpen(false);
        };
        document.addEventListener('pointerdown', outside, true);
        window.addEventListener('resize', position);
        window.addEventListener('scroll', position, true);
        return () => {
            if (panel.isConnected && panel.matches(':popover-open')) panel.hidePopover();
            document.removeEventListener('pointerdown', outside, true);
            window.removeEventListener('resize', position);
            window.removeEventListener('scroll', position, true);
        };
    }, [open, disabled, options.length]);
    useEffect(() => { if (open) document.getElementById(`${menuID}-${active}`)?.scrollIntoView({ block: 'nearest' }); }, [open, active, menuID]);
    useEffect(() => {
        const form = native.current?.form;
        const reset = () => { setInternal(String(defaultValue ?? '')); setInvalid(false); setOpen(false); };
        form?.addEventListener('reset', reset);
        return () => form?.removeEventListener('reset', reset);
    }, [defaultValue]);

    return <span className={`select-control ${className}`} data-invalid={invalid || !!error || undefined}>
        <button type="button" id={triggerID} ref={trigger} className="select-trigger" role="combobox" aria-haspopup="listbox" aria-expanded={open && !disabled} aria-controls={menuID} aria-activedescendant={open ? `${menuID}-${active}` : undefined} aria-label={props['aria-label']} aria-labelledby={props['aria-labelledby']} aria-describedby={[props['aria-describedby'], error ? `${fieldID}-error` : ''].filter(Boolean).join(' ') || undefined} aria-required={required} aria-invalid={invalid || !!error || props['aria-invalid']} disabled={disabled || !options.length} title={props.title} onClick={event => { event.preventDefault(); setActive(selectedIndex); setOpen(!open); }} onKeyDown={event => {
            if (event.key === 'Tab') { setOpen(false); return; }
            if (event.key === 'Escape' && open) { event.preventDefault(); event.stopPropagation(); setOpen(false); return; }
            if (['ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter', ' '].includes(event.key)) {
                event.preventDefault();
                if (event.key === 'ArrowDown' || event.key === 'ArrowUp') move(event.key === 'ArrowDown' ? 1 : -1);
                else if (event.key === 'Home' || event.key === 'End') { const indexes = options.map((option, i) => option.disabled ? -1 : i).filter(i => i >= 0); setActive((event.key === 'Home' ? indexes[0] : indexes.at(-1)) ?? 0); setOpen(true); }
                else if (open && options[active]) choose(options[active]);
                else { setActive(selectedIndex); setOpen(true); }
            } else if (event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey) {
                const now = Date.now();
                search.current = { text: now - search.current.at < 600 ? search.current.text + event.key : event.key, at: now };
                const index = options.findIndex((option, i) => !option.disabled && native.current?.options[i]?.text.toLocaleLowerCase().startsWith(search.current.text.toLocaleLowerCase()));
                if (index >= 0) { setActive(index); setOpen(true); }
            }
        }}><span className="select-value">{selected?.label}</span><ChevronDown size={15} aria-hidden="true"/></button>
        <select {...props} id={fieldID} ref={native} hidden aria-hidden="true" tabIndex={-1} required={required} disabled={disabled} value={selectedValue} onInvalid={event => { event.preventDefault(); setInvalid(true); trigger.current?.focus(); setActive(selectedIndex); setOpen(true); onInvalid?.(event); }} onChange={event => { setInternal(event.target.value); setInvalid(false); onChange?.(event); }}>{children}</select>
        <span ref={menu} id={menuID} popover="manual" role="listbox" aria-label={props['aria-label']} className="select-menu">{options.map((option, index) => <span key={option.value} id={`${menuID}-${index}`} role="option" aria-selected={option.value === selectedValue} aria-disabled={option.disabled || undefined} className={`select-option ${active === index ? 'is-active' : ''}`} onPointerMove={() => { if (!option.disabled) setActive(index); }} onClick={event => { event.preventDefault(); choose(option); }}><span>{option.label}</span>{option.value === selectedValue && <Check size={15} aria-hidden="true"/>}</span>)}</span>
        <FieldError id={fieldID}/>
    </span>;
}
