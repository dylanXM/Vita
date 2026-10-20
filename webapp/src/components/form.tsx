'use client';
import { createContext, useContext, useId, useState, type ComponentPropsWithRef, type FormEvent, type InputHTMLAttributes, type TextareaHTMLAttributes } from 'react';
import { CircleAlert } from 'lucide-react';
import type { MessageKey } from '../lib/i18n';
type T = (key: MessageKey) => string;
type Reason = { key: MessageKey; value?: string };
type Control = HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
const FormContext = createContext<{ errors: Record<string, Reason>; t: T } | null>(null);

function reason(control: Control): Reason | null {
    const validity = control.validity;
    if (!control.willValidate || validity.valid) return null;
    if (validity.valueMissing) return { key: control instanceof HTMLSelectElement ? 'validationSelection' : control instanceof HTMLInputElement && control.type === 'checkbox' ? 'validationCheckbox' : 'validationRequired' };
    if (validity.typeMismatch && control instanceof HTMLInputElement && control.type === 'email') return { key: 'validationEmail' };
    if (validity.tooShort) return { key: 'validationMinLength', value: control.getAttribute('minlength') || '' };
    if (validity.tooLong) return { key: 'validationMaxLength', value: control.getAttribute('maxlength') || '' };
    if (validity.rangeUnderflow) return { key: 'validationMin', value: control.getAttribute('min') || '' };
    if (validity.rangeOverflow) return { key: 'validationMax', value: control.getAttribute('max') || '' };
    if (validity.badInput) return { key: 'validationNumber' };
    if (validity.stepMismatch) return { key: 'validationStep' };
    return { key: 'validationFormat' };
}
function isControl(target: EventTarget | null): target is Control {
    return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement;
}
export function useFieldError(id: string) {
    const context = useContext(FormContext);
    const error = context?.errors[id];
    return error && context ? context.t(error.key).replace('@value', error.value || '') : '';
}
export function FieldError({ id }: { id: string }) {
    const message = useFieldError(id);
    return message ? <span className="field-error" id={`${id}-error`}><CircleAlert size={14} aria-hidden="true"/><span>{message}</span></span> : null;
}
export function Form({ t, children, onSubmit, onInputCapture, onChangeCapture, onInvalidCapture, onReset, ...props }: ComponentPropsWithRef<'form'> & { t: T }) {
    const [errors, setErrors] = useState<Record<string, Reason>>({});
    function update(event: FormEvent<HTMLFormElement>) {
        const control = event.target;
        if (!isControl(control)) return;
        setErrors(previous => {
            if (!previous[control.id]) return previous;
            const next = { ...previous }; const error = reason(control);
            if (error) next[control.id] = error; else delete next[control.id];
            return next;
        });
    }
    return <FormContext.Provider value={{ errors, t }}><form {...props} noValidate onSubmit={event => {
        const next: Record<string, Reason> = {};
        let first: Control | undefined;
        for (const element of Array.from(event.currentTarget.elements)) {
            if (!isControl(element)) continue;
            const error = reason(element);
            if (error) { next[element.id] = error; first ||= element; }
        }
        setErrors(next);
        if (first) {
            event.preventDefault();
            first.dispatchEvent(new Event('invalid', { cancelable: true }));
            if (!first.hidden) first.focus();
            return;
        }
        void onSubmit?.(event);
    }} onInvalidCapture={event => {
        event.preventDefault();
        if (isControl(event.target)) { const control = event.target; const error = reason(control); if (error) setErrors(previous => ({ ...previous, [control.id]: error })); }
        onInvalidCapture?.(event);
    }} onInputCapture={event => { update(event); onInputCapture?.(event); }} onChangeCapture={event => { update(event); onChangeCapture?.(event); }} onReset={event => { setErrors({}); onReset?.(event); }}>
        {Object.keys(errors).length > 0 && <div className="form-error-summary" role="alert"><CircleAlert size={17} aria-hidden="true"/><span>{t('validationSummary')}</span></div>}{children}
    </form></FormContext.Provider>;
}
export function Input({ id, ...props }: InputHTMLAttributes<HTMLInputElement>) {
    const generatedID = useId(); const fieldID = id || generatedID; const error = useFieldError(fieldID);
    return <><input {...props} id={fieldID} aria-invalid={error ? true : props['aria-invalid']} aria-describedby={[props['aria-describedby'], error ? `${fieldID}-error` : ''].filter(Boolean).join(' ') || undefined}/><FieldError id={fieldID}/></>;
}
export function Textarea({ id, ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
    const generatedID = useId(); const fieldID = id || generatedID; const error = useFieldError(fieldID);
    return <><textarea {...props} id={fieldID} aria-invalid={error ? true : props['aria-invalid']} aria-describedby={[props['aria-describedby'], error ? `${fieldID}-error` : ''].filter(Boolean).join(' ') || undefined}/><FieldError id={fieldID}/></>;
}
