import 'package:flutter/widgets.dart';

import 'constants.dart';
import 'supported_locales.dart';

enum LegalDocumentType { privacy, terms }

const String privacyPolicyVersion = '2026-09-20';
const String termsOfServiceVersion = '2026-09-20';

class LegalDocument {
  const LegalDocument({
    required this.updatedLabel,
    required this.summary,
    required this.body,
  });

  final String updatedLabel;
  final String summary;
  final String body;
}

LegalDocument legalDocumentFor(Locale locale, LegalDocumentType type) {
  final tag = vitaLocaleTag(locale);
  final documents =
      type == LegalDocumentType.privacy ? privacyDocuments : termsDocuments;
  return documents[tag] ?? documents['en']!;
}

final Map<String, LegalDocument> privacyDocuments = {
  'en': LegalDocument(
    updatedLabel: 'Effective date: $privacyPolicyVersion',
    summary:
        'This policy explains what Vita collects, why it is used, and the choices you have.',
    body: '''1. Information we collect
We process your email address, encrypted authentication credentials, profile settings and the companion profiles you create. To provide conversations and life features, we process messages, voice recordings, uploaded media, memories and experience activity. We may also process app version, language, device push token, purchase status and basic usage events.

2. How we use information
We use this information to create and secure your account, deliver messages and media, maintain companion continuity, provide purchases and support, prevent abuse, diagnose faults and improve Vita. We do not sell personal information.

3. AI and service providers
Conversation prompts and requested media may be sent to configured AI providers to generate replies, images, speech or transcriptions. Payments are processed by Apple, Google, RevenueCat or Stripe as applicable. Email, storage and notification providers process only the data needed to deliver their service.

4. Storage and security
Information is retained only while needed for the service, legal obligations, fraud prevention and dispute handling. We use access controls, encryption in transit and restricted administrative access. No online system can guarantee absolute security.

5. Your choices and rights
You can review or correct account and companion information in Vita, control device permissions in system settings, sign out, or permanently delete your account from Settings. Store subscriptions must be cancelled separately in the relevant store.

6. Children
Vita is not intended for children below the minimum age required in their country. Minors must use Vita only with permission and supervision from a parent or legal guardian.

7. Changes and contact
We will present material policy changes before they take effect when renewed consent is required. Privacy questions and requests can be sent to $supportEmail.''',
  ),
  'zh-Hans': LegalDocument(
    updatedLabel: '生效日期：$privacyPolicyVersion',
    summary: '本政策说明 Vita 收集哪些信息、为何使用这些信息，以及你可以如何管理自己的信息。',
    body: '''一、我们收集的信息
我们会处理你的邮箱地址、加密后的身份验证凭据、个人设置以及你创建的角色资料。为了提供聊天和生活功能，我们会处理消息、语音录音、上传的媒体、记忆及互动记录。我们还可能处理 App 版本、语言、设备推送令牌、购买状态和必要的使用事件。

二、信息的使用方式
相关信息用于创建和保护账户、传递消息与媒体、保持角色设定和记忆连续性、提供购买及客服支持、防止滥用、排查故障和改进 Vita。我们不会出售你的个人信息。

三、AI 与第三方服务
为生成回复、图片、语音或转写内容，相关提示词和媒体可能会发送给已配置的 AI 服务商。支付可能由 Apple、Google、RevenueCat 或 Stripe 处理。邮件、存储和推送服务商仅处理完成相应服务所必需的信息。

四、存储与安全
我们仅在提供服务、履行法定义务、防范欺诈及处理争议所需的期限内保存信息，并采取传输加密、访问控制和后台权限限制等措施。任何互联网服务都无法保证绝对安全。

五、你的权利
你可以在 Vita 中查看或修改账户和角色信息，在系统设置中管理设备权限，也可以退出登录或在“设置”中永久注销账户。应用商店订阅需要在相应商店中另行取消。

六、未成年人保护
Vita 不面向未达到所在地最低法定年龄的儿童。未成年人应在父母或法定监护人同意和指导下使用 Vita。

七、政策变更与联系我们
如发生需要重新取得同意的重大变更，我们会在变更生效前明确提示。隐私问题或权利请求可发送至 $supportEmail。''',
  ),
  'zh-Hant': LegalDocument(
    updatedLabel: '生效日期：$privacyPolicyVersion',
    summary: '本政策說明 Vita 收集哪些資訊、使用目的，以及你可以如何管理自己的資訊。',
    body: '''一、我們收集的資訊
我們會處理你的電子郵件地址、加密的驗證憑證、個人設定及你建立的角色資料。為提供聊天與生活功能，我們會處理訊息、語音錄音、上傳媒體、記憶與互動記錄，也可能處理 App 版本、語言、裝置推送權杖、購買狀態及必要的使用事件。

二、使用方式
資訊用於建立及保護帳戶、傳送訊息與媒體、維持角色設定與記憶連續性、提供購買及客服支援、防止濫用、診斷問題與改善 Vita。我們不會出售個人資訊。

三、AI 與服務供應商
為產生回覆、圖片、語音或轉錄，相關提示與媒體可能傳送至已設定的 AI 供應商。付款可能由 Apple、Google、RevenueCat 或 Stripe 處理。郵件、儲存與推送供應商只處理提供服務所需的資料。

四、保存與安全
資料只會在服務、法律義務、防詐及爭議處理所需期間保存。我們採用傳輸加密、存取控制與受限的管理權限，但任何網路系統都無法保證絕對安全。

五、你的權利
你可在 Vita 查看或更正帳戶與角色資訊、在系統設定管理裝置權限、登出或於「設定」永久刪除帳戶。商店訂閱須另行在相關商店取消。

六、未成年人
Vita 不供未達所在地最低法定年齡的兒童使用。未成年人須取得父母或法定監護人同意並在其指導下使用。

七、變更與聯絡
如有需要重新取得同意的重大變更，我們會在生效前清楚提示。隱私問題或權利請求可寄至 $supportEmail。''',
  ),
  'es': LegalDocument(
    updatedLabel: 'Fecha de entrada en vigor: $privacyPolicyVersion',
    summary:
        'Esta política explica qué datos trata Vita, para qué se usan y qué opciones tienes.',
    body: '''1. Datos tratados
Tratamos tu correo, credenciales cifradas, ajustes, perfiles de compañeros, mensajes, grabaciones de voz, archivos, recuerdos y actividad. También podemos tratar la versión de la app, idioma, token de notificaciones, estado de compras y eventos técnicos necesarios.

2. Finalidades
Usamos los datos para crear y proteger la cuenta, ofrecer conversaciones y contenido, conservar la continuidad del compañero, gestionar compras y soporte, prevenir abusos, corregir fallos y mejorar Vita. No vendemos datos personales.

3. Proveedores
Las solicitudes y archivos necesarios pueden enviarse a proveedores de IA para generar texto, imágenes, voz o transcripciones. Apple, Google, RevenueCat o Stripe pueden procesar pagos. Los proveedores de correo, almacenamiento y notificaciones reciben solo los datos necesarios.

4. Conservación y seguridad
Conservamos los datos mientras sean necesarios para el servicio, obligaciones legales, prevención del fraude o reclamaciones. Aplicamos cifrado en tránsito y controles de acceso.

5. Tus derechos
Puedes corregir datos, gestionar permisos, cerrar sesión o eliminar permanentemente tu cuenta desde Ajustes. Las suscripciones deben cancelarse por separado en la tienda.

6. Menores y contacto
Los menores deben cumplir la edad mínima local y contar con autorización de su tutor. Para consultas o solicitudes: $supportEmail.''',
  ),
  'pt': LegalDocument(
    updatedLabel: 'Data de vigência: $privacyPolicyVersion',
    summary:
        'Esta política explica quais dados o Vita trata, por que são usados e quais escolhas você tem.',
    body: '''1. Dados tratados
Tratamos seu e-mail, credenciais criptografadas, preferências, perfis de companheiros, mensagens, gravações de voz, mídias, memórias e atividades. Também podemos tratar versão do app, idioma, token de notificações, estado de compras e eventos técnicos necessários.

2. Finalidades
Usamos os dados para criar e proteger a conta, entregar conversas e mídia, manter a continuidade do companheiro, fornecer compras e suporte, prevenir abuso, corrigir falhas e melhorar o Vita. Não vendemos dados pessoais.

3. Prestadores
Solicitações e mídias necessárias podem ser enviadas a provedores de IA para gerar texto, imagens, voz ou transcrições. Apple, Google, RevenueCat ou Stripe podem processar pagamentos. Serviços de e-mail, armazenamento e notificações recebem apenas os dados necessários.

4. Retenção e segurança
Mantemos os dados pelo tempo necessário ao serviço, obrigações legais, prevenção de fraude e disputas. Usamos criptografia em trânsito e controles de acesso.

5. Seus direitos
Você pode corrigir dados, controlar permissões, sair ou excluir permanentemente a conta em Configurações. Assinaturas devem ser canceladas separadamente na loja.

6. Menores e contato
Menores devem cumprir a idade mínima local e ter autorização do responsável. Dúvidas e solicitações: $supportEmail.''',
  ),
  'ja': LegalDocument(
    updatedLabel: '発効日：$privacyPolicyVersion',
    summary: '本ポリシーは、Vitaが取り扱う情報、利用目的、お客様の選択肢を説明します。',
    body: '''1. 取得する情報
メールアドレス、暗号化された認証情報、設定、作成したコンパニオン情報、メッセージ、音声、アップロード媒体、思い出、利用履歴を処理します。アプリ版、言語、通知トークン、購入状況、必要な技術イベントも処理する場合があります。

2. 利用目的
アカウント保護、会話と媒体の提供、コンパニオンの継続性、購入とサポート、不正防止、障害解析、Vitaの改善に利用します。個人情報を販売しません。

3. 外部サービス
文章、画像、音声、文字起こしの生成に必要な入力は、設定されたAI提供者へ送信される場合があります。決済はApple、Google、RevenueCat、Stripeが処理する場合があります。メール、保存、通知事業者には必要な情報だけを渡します。

4. 保存と安全
サービス、法令、不正防止、紛争対応に必要な期間だけ保存し、通信暗号化とアクセス制御を行います。

5. お客様の権利
情報の修正、権限管理、ログアウト、設定画面からのアカウント削除ができます。ストア購読は別途解約してください。

6. 未成年者と連絡先
地域の最低年齢を満たさない方は利用できません。未成年者は保護者の同意と監督が必要です。お問い合わせ：$supportEmail。''',
  ),
  'ko': LegalDocument(
    updatedLabel: '시행일: $privacyPolicyVersion',
    summary: '이 정책은 Vita가 처리하는 정보, 이용 목적 및 사용자의 선택권을 설명합니다.',
    body: '''1. 처리하는 정보
이메일, 암호화된 인증 정보, 설정, 생성한 컴패니언 프로필, 메시지, 음성 녹음, 업로드 미디어, 기억 및 활동을 처리합니다. 앱 버전, 언어, 푸시 토큰, 구매 상태 및 필요한 기술 이벤트도 처리할 수 있습니다.

2. 이용 목적
계정 생성과 보호, 대화와 미디어 제공, 컴패니언 연속성 유지, 구매와 지원, 악용 방지, 오류 진단 및 Vita 개선에 사용합니다. 개인정보를 판매하지 않습니다.

3. 외부 제공자
텍스트, 이미지, 음성 또는 전사를 생성하는 데 필요한 요청과 미디어가 설정된 AI 제공자에게 전송될 수 있습니다. 결제는 Apple, Google, RevenueCat 또는 Stripe가 처리할 수 있습니다. 이메일, 저장소 및 알림 제공자는 서비스에 필요한 정보만 처리합니다.

4. 보관과 보안
서비스, 법적 의무, 사기 방지와 분쟁 처리에 필요한 기간만 보관하며 전송 암호화와 접근 통제를 적용합니다.

5. 사용자 권리
정보 수정, 권한 관리, 로그아웃 및 설정에서 계정 영구 삭제가 가능합니다. 스토어 구독은 별도로 취소해야 합니다.

6. 미성년자와 문의
현지 최소 연령 미만은 이용할 수 없으며 미성년자는 보호자 동의와 감독이 필요합니다. 문의: $supportEmail.''',
  ),
  'ar': LegalDocument(
    updatedLabel: 'تاريخ السريان: $privacyPolicyVersion',
    summary:
        'توضح هذه السياسة المعلومات التي يعالجها Vita وأغراض استخدامها وخياراتك.',
    body: '''1. المعلومات التي نعالجها
نعالج بريدك الإلكتروني وبيانات التحقق المشفرة والإعدادات وملفات الرفقاء والرسائل والتسجيلات الصوتية والوسائط والذكريات والنشاط. وقد نعالج إصدار التطبيق واللغة ورمز الإشعارات وحالة المشتريات والأحداث التقنية الضرورية.

2. أغراض الاستخدام
نستخدم المعلومات لإنشاء الحساب وحمايته وتقديم المحادثات والوسائط والحفاظ على استمرارية الرفيق وإدارة المشتريات والدعم ومنع الإساءة وتشخيص الأعطال وتحسين Vita. لا نبيع المعلومات الشخصية.

3. مقدمو الخدمات
قد تُرسل الطلبات والوسائط اللازمة إلى مقدمي خدمات الذكاء الاصطناعي لإنشاء النصوص أو الصور أو الصوت أو التفريغ. وقد تعالج Apple أو Google أو RevenueCat أو Stripe المدفوعات. يعالج مقدمو البريد والتخزين والإشعارات البيانات اللازمة فقط.

4. الاحتفاظ والأمان
نحتفظ بالمعلومات للمدة اللازمة للخدمة والالتزامات القانونية ومنع الاحتيال وتسوية النزاعات، ونستخدم تشفير النقل وضوابط الوصول.

5. حقوقك
يمكنك تصحيح المعلومات وإدارة الأذونات وتسجيل الخروج أو حذف الحساب نهائيًا من الإعدادات. يجب إلغاء اشتراكات المتجر بشكل منفصل.

6. القاصرون والتواصل
يجب استيفاء الحد الأدنى للعمر المحلي، ويحتاج القاصر إلى موافقة ولي الأمر وإشرافه. للتواصل: $supportEmail.''',
  ),
};

final Map<String, LegalDocument> termsDocuments = {
  'en': LegalDocument(
    updatedLabel: 'Effective date: $termsOfServiceVersion',
    summary:
        'These terms govern your use of Vita and explain the rules of the service.',
    body: '''1. Accepting these terms
By creating a Vita account, you confirm that you have read and accepted these Terms and the Privacy Policy. If you do not agree, do not register or use the service.

2. The service
Vita provides fictional AI companion conversations, generated life events, memories and optional paid digital experiences. AI output may be inaccurate, repetitive or inappropriate and must not be treated as professional, medical, legal, financial or emergency advice. Companions are fictional and are not real people.

3. Your account and content
You must provide accurate registration information, protect your credentials and remain responsible for activity under your account. You retain rights in content you submit and grant Vita the limited permission needed to process it and provide the service.

4. Acceptable use
Do not use Vita to break the law, harm or exploit others, infringe rights, obtain unauthorized access, distribute malware, manipulate purchases, automate abuse or submit content you have no right to use. We may restrict or terminate accounts that violate these rules.

5. Purchases
Subscriptions and digital credits may be offered through the applicable store or payment provider. Prices and benefits are shown before purchase. Store subscriptions renew and are cancelled under the store's rules. Except where required by law or store policy, consumed digital benefits are not refundable.

6. Availability and termination
Features may change, be suspended or end. You may stop using Vita or delete your account at any time. We may suspend access where reasonably necessary for security, legal compliance or material breach.

7. Responsibility and contact
Vita is provided with reasonable care but without a promise that it will always be uninterrupted or error-free. Mandatory consumer rights are not limited by these Terms. Questions can be sent to $supportEmail.''',
  ),
  'zh-Hans': LegalDocument(
    updatedLabel: '生效日期：$termsOfServiceVersion',
    summary: '本协议约定你使用 Vita 时适用的服务规则和双方权利义务。',
    body: '''一、接受协议
创建 Vita 账户即表示你已阅读并同意本《用户协议》和《隐私政策》。如果你不同意，请不要注册或使用本服务。

二、服务内容
Vita 提供虚构 AI 角色聊天、生成式生活事件、记忆以及可选的付费数字体验。AI 内容可能不准确、重复或不恰当，不应作为医疗、法律、财务、专业或紧急建议。所有角色均为虚构形象，不是真实人物。

三、账户与用户内容
你应提供准确的注册信息、妥善保管登录凭据，并对账户下的操作负责。你保留所提交内容的相关权利，同时授权 Vita 在提供服务所必需的范围内处理这些内容。

四、使用规范
不得利用 Vita 违法、伤害或剥削他人、侵犯他人权利、未经授权访问系统、传播恶意程序、操纵购买、批量滥用服务或提交无权使用的内容。违反规则时，我们可以限制或终止相关账户。

五、付费服务
订阅和数字积分可能通过应用商店或支付服务商提供，价格和权益会在购买前展示。订阅续期及取消遵循相应商店规则。除法律或商店规则另有规定外，已经消耗的数字权益不予退款。

六、服务变更与终止
功能可能发生调整、暂停或停止。你可以随时停止使用 Vita 或注销账户。为保障安全、遵守法律或处理重大违约，我们可以合理暂停服务。

七、责任与联系我们
我们会以合理谨慎的方式提供 Vita，但不保证服务永不中断或完全无误。本协议不限制法律规定的消费者权利。相关问题可发送至 $supportEmail。''',
  ),
  'zh-Hant': LegalDocument(
    updatedLabel: '生效日期：$termsOfServiceVersion',
    summary: '本協議規範你使用 Vita 時適用的服務規則與雙方權利義務。',
    body: '''一、接受協議
建立 Vita 帳戶即表示你已閱讀並同意本《使用者協議》與《隱私政策》。如不同意，請勿註冊或使用服務。

二、服務內容
Vita 提供虛構 AI 角色聊天、生成式生活事件、記憶及可選的付費數位體驗。AI 內容可能不準確、重複或不適當，不應作為醫療、法律、財務、專業或緊急建議。所有角色均為虛構形象，並非真人。

三、帳戶與內容
你應提供正確的註冊資料、保護登入憑證，並對帳戶活動負責。你保留提交內容的相關權利，同時授權 Vita 在提供服務所需範圍內處理內容。

四、使用規範
不得利用 Vita 違法、傷害或剝削他人、侵害權利、未經授權存取、散播惡意程式、操縱購買、自動化濫用服務或提交無權使用的內容。違規時我們可限制或終止帳戶。

五、付費服務
訂閱與數位點數可能由應用程式商店或支付商提供，價格與權益會於購買前顯示。續訂與取消依商店規則辦理。除法律或商店政策要求外，已使用的數位權益不予退款。

六、變更與終止
功能可能調整、暫停或停止。你可隨時停止使用或刪除帳戶。基於安全、法律遵循或重大違約，我們可合理暫停服務。

七、責任與聯絡
我們會合理謹慎地提供 Vita，但不保證服務永不中斷或完全無誤。法定消費者權利不受限制。問題可寄至 $supportEmail。''',
  ),
  'es': LegalDocument(
    updatedLabel: 'Fecha de entrada en vigor: $termsOfServiceVersion',
    summary:
        'Estas condiciones regulan el uso de Vita y las reglas del servicio.',
    body: '''1. Aceptación
Al crear una cuenta confirmas que has leído y aceptado estas Condiciones y la Política de privacidad. Si no estás de acuerdo, no te registres ni uses el servicio.

2. Servicio e IA
Vita ofrece compañeros ficticios de IA, conversaciones, eventos, recuerdos y experiencias digitales opcionales. El contenido de IA puede ser inexacto o inapropiado y no sustituye asesoramiento profesional, médico, legal, financiero o de emergencia.

3. Cuenta y contenido
Debes proteger tus credenciales y eres responsable de tu cuenta. Conservas tus derechos sobre lo que envías y autorizas su tratamiento limitado para prestar el servicio.

4. Uso aceptable
No uses Vita para infringir la ley o derechos, causar daño, acceder sin autorización, distribuir software malicioso, manipular compras o automatizar abusos. Podemos limitar cuentas infractoras.

5. Compras y disponibilidad
Los precios y beneficios se muestran antes de comprar. Renovaciones, cancelaciones y reembolsos siguen las reglas de la tienda y la ley. Las funciones pueden cambiar o suspenderse.

6. Contacto
Los derechos obligatorios del consumidor no se limitan. Consultas: $supportEmail.''',
  ),
  'pt': LegalDocument(
    updatedLabel: 'Data de vigência: $termsOfServiceVersion',
    summary: 'Estes termos regem o uso do Vita e as regras do serviço.',
    body: '''1. Aceitação
Ao criar uma conta, você confirma que leu e aceitou estes Termos e a Política de Privacidade. Se não concordar, não se cadastre nem use o serviço.

2. Serviço e IA
O Vita oferece companheiros fictícios de IA, conversas, eventos, memórias e experiências digitais opcionais. Conteúdo de IA pode ser impreciso ou inadequado e não substitui orientação profissional, médica, jurídica, financeira ou de emergência.

3. Conta e conteúdo
Proteja suas credenciais e responda pelas atividades da conta. Você mantém os direitos sobre o conteúdo enviado e concede permissão limitada para processá-lo e prestar o serviço.

4. Uso aceitável
Não use o Vita para violar leis ou direitos, causar danos, obter acesso indevido, distribuir malware, manipular compras ou automatizar abuso. Podemos limitar contas infratoras.

5. Compras e disponibilidade
Preços e benefícios são mostrados antes da compra. Renovação, cancelamento e reembolso seguem as regras da loja e a lei. Recursos podem mudar ou ser suspensos.

6. Contato
Direitos obrigatórios do consumidor permanecem válidos. Dúvidas: $supportEmail.''',
  ),
  'ja': LegalDocument(
    updatedLabel: '発効日：$termsOfServiceVersion',
    summary: '本規約はVitaの利用条件とサービス上のルールを定めます。',
    body: '''1. 同意
アカウント作成により、本規約とプライバシーポリシーを読み同意したことを確認します。同意しない場合は登録・利用しないでください。

2. サービスとAI
Vitaは架空のAIコンパニオンとの会話、生活イベント、思い出、有料デジタル体験を提供します。AI出力は不正確または不適切な場合があり、医療、法律、金融、専門的・緊急助言ではありません。

3. アカウントとコンテンツ
認証情報を保護し、アカウントの活動に責任を負ってください。投稿内容の権利は利用者に残り、サービス提供に必要な限定的処理をVitaに許可します。

4. 禁止事項
違法行為、他者への危害、権利侵害、不正アクセス、マルウェア、購入操作、自動的な濫用は禁止です。違反アカウントを制限できるものとします。

5. 購入と提供
価格と特典は購入前に表示します。更新、解約、返金はストア規則と法令に従います。機能は変更・停止される場合があります。

6. お問い合わせ
法定の消費者権利は制限されません。お問い合わせ：$supportEmail。''',
  ),
  'ko': LegalDocument(
    updatedLabel: '시행일: $termsOfServiceVersion',
    summary: '본 약관은 Vita 이용과 서비스 규칙을 정합니다.',
    body: '''1. 동의
계정을 만들면 본 약관과 개인정보 처리방침을 읽고 동의했음을 확인합니다. 동의하지 않으면 등록하거나 서비스를 이용하지 마십시오.

2. 서비스와 AI
Vita는 가상의 AI 컴패니언 대화, 생활 이벤트, 기억 및 선택형 유료 디지털 경험을 제공합니다. AI 결과는 부정확하거나 부적절할 수 있으며 전문·의료·법률·금융·응급 조언이 아닙니다.

3. 계정과 콘텐츠
인증 정보를 보호하고 계정 활동에 책임을 져야 합니다. 제출한 콘텐츠의 권리는 사용자에게 있으며 서비스 제공에 필요한 제한적 처리 권한을 Vita에 부여합니다.

4. 허용되는 이용
법률 또는 권리 침해, 타인에게 피해, 무단 접근, 악성 코드, 구매 조작, 자동화된 남용을 금지합니다. 위반 계정은 제한될 수 있습니다.

5. 구매와 제공
가격과 혜택은 구매 전에 표시됩니다. 갱신, 취소, 환불은 스토어 규칙과 법률을 따릅니다. 기능은 변경되거나 중단될 수 있습니다.

6. 문의
법정 소비자 권리는 제한되지 않습니다. 문의: $supportEmail.''',
  ),
  'ar': LegalDocument(
    updatedLabel: 'تاريخ السريان: $termsOfServiceVersion',
    summary: 'تحكم هذه الشروط استخدام Vita وقواعد الخدمة.',
    body: '''1. القبول
بإنشاء حساب تؤكد قراءة هذه الشروط وسياسة الخصوصية والموافقة عليهما. إذا لم توافق فلا تسجل أو تستخدم الخدمة.

2. الخدمة والذكاء الاصطناعي
يوفر Vita رفقاء خياليين بالذكاء الاصطناعي ومحادثات وأحداثًا وذكريات وتجارب رقمية اختيارية. قد يكون محتوى الذكاء الاصطناعي غير دقيق أو غير مناسب ولا يعد نصيحة مهنية أو طبية أو قانونية أو مالية أو طارئة.

3. الحساب والمحتوى
يجب حماية بيانات الدخول وتتحمل مسؤولية نشاط الحساب. تحتفظ بحقوق المحتوى الذي ترسله وتمنح Vita الإذن المحدود اللازم لمعالجته وتقديم الخدمة.

4. الاستخدام المقبول
يُحظر انتهاك القانون أو الحقوق أو إيذاء الآخرين أو الوصول غير المصرح أو نشر البرمجيات الضارة أو التلاعب بالمشتريات أو إساءة الاستخدام الآلية. قد نقيّد الحسابات المخالفة.

5. المشتريات والتوفر
تظهر الأسعار والمزايا قبل الشراء. تخضع التجديدات والإلغاءات والمبالغ المستردة لقواعد المتجر والقانون. قد تتغير الميزات أو تتوقف.

6. التواصل
لا تُقيّد حقوق المستهلك الإلزامية. للاستفسار: $supportEmail.''',
  ),
};
