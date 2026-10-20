CREATE TABLE IF NOT EXISTS legal_documents (
    id TEXT PRIMARY KEY,
    environment TEXT NOT NULL CHECK (environment IN ('dev', 'beta', 'prod')),
    document_type TEXT NOT NULL CHECK (document_type IN ('privacy', 'terms')),
    version TEXT NOT NULL,
    title TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    content TEXT NOT NULL,
    is_effective BOOLEAN NOT NULL DEFAULT false,
    published_at TIMESTAMP,
    updated_by TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(environment, document_type, version)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_legal_documents_effective
    ON legal_documents(environment, document_type) WHERE is_effective;
CREATE INDEX IF NOT EXISTS idx_legal_documents_list
    ON legal_documents(environment, document_type, updated_at DESC);

INSERT INTO legal_documents(id,environment,document_type,version,title,summary,content,is_effective,published_at,updated_by)
SELECT 'default-' || environment || '-privacy', environment, 'privacy', '2026-09-20', 'Privacy Policy',
'This policy explains what Vita collects, why it is used, and the choices you have.',
$$1. Information we collect
We process your email address, encrypted authentication credentials, profile settings, companion profiles, messages, voice recordings, uploaded media, memories, purchase status and necessary usage events.

2. How we use information
We use this information to create and secure your account, deliver conversations and media, maintain companion continuity, provide purchases and support, prevent abuse, diagnose faults and improve Vita. We do not sell personal information.

3. AI and service providers
Requests and media may be sent to configured AI providers to generate text, images, speech or transcriptions. Payments and delivery services process only the data needed to provide their service.

4. Storage and security
Information is retained only while needed for the service, legal obligations, fraud prevention and dispute handling. We use access controls and encryption in transit.

5. Your choices and rights
You can correct account information, manage device permissions, sign out or permanently delete your account from Settings. Store subscriptions must be cancelled separately.

6. Children and contact
Vita is not intended for children below the minimum age required in their country. Privacy questions can be sent to support@vita.app.$$,
true,CURRENT_TIMESTAMP,'system'
FROM (VALUES ('dev'),('beta'),('prod')) AS environments(environment)
ON CONFLICT(environment,document_type,version) DO NOTHING;

INSERT INTO legal_documents(id,environment,document_type,version,title,summary,content,is_effective,published_at,updated_by)
SELECT 'default-' || environment || '-terms', environment, 'terms', '2026-09-20', 'Terms of Service',
'These terms govern your use of Vita and explain the rules of the service.',
$$1. Accepting these terms
By creating a Vita account, you confirm that you have read and accepted these Terms and the Privacy Policy. If you do not agree, do not register or use the service.

2. The service
Vita provides fictional AI companion conversations, generated life events, memories and optional paid digital experiences. AI output may be inaccurate and must not be treated as professional, medical, legal, financial or emergency advice.

3. Your account and content
You must protect your credentials and remain responsible for activity under your account. You retain rights in submitted content and grant Vita the limited permission needed to process it and provide the service.

4. Acceptable use
Do not use Vita to break the law, harm others, infringe rights, obtain unauthorized access, distribute malware, manipulate purchases or automate abuse.

5. Purchases
Prices and benefits are shown before purchase. Store subscriptions renew and are cancelled under store rules. Consumed digital benefits are not refundable except where required by law or store policy.

6. Availability and contact
Features may change, be suspended or end. You may stop using Vita or delete your account at any time. Questions can be sent to support@vita.app.$$,
true,CURRENT_TIMESTAMP,'system'
FROM (VALUES ('dev'),('beta'),('prod')) AS environments(environment)
ON CONFLICT(environment,document_type,version) DO NOTHING;
