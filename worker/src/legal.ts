// Legal page content — iOS App ToS and nehan.ai Service ToS

export function iosToSContent(lang: string): string {
  if (lang === 'en') {
    return `
    <h1>iOS App Terms of Service</h1>
    <p>Last updated: April 11, 2026</p>

    <h2>1. Service Description</h2>
    <p>nehan.ai is a life log recording application for iOS. The app records location data, HealthKit data, and user memos, and generates daily reports using on-device AI.</p>

    <h2>2. Data Collection</h2>
    <ul>
      <li><strong>Location data</strong>: Background location tracking and reverse-geocoded place names. Explicit user permission is required.</li>
      <li><strong>HealthKit data</strong>: Sleep analysis, steps, heart rate, mindfulness, and other health metrics. All processing is performed locally on your device. Explicit user permission is required.</li>
      <li><strong>User input</strong>: Memos, dream diary entries, and blog content you create.</li>
    </ul>

    <h2>3. On-Device AI</h2>
    <p>Text generation uses Apple Intelligence (Foundation Models) and image generation uses Image Playground. All AI processing is performed entirely on your device. No data is sent to external AI services.</p>

    <h2>4. Data Sync</h2>
    <p>Your data is transmitted via HTTPS to our servers (Cloudflare Workers) for backup and blog publishing. See our <a href="/terms/privacy/en">Privacy Policy</a> for details.</p>

    <h2>5. Prohibited Activities</h2>
    <ul>
      <li>Unauthorized use of the API, decompilation, or reverse engineering</li>
      <li>Unauthorized use of another person's account or tokens</li>
      <li>Placing excessive load on the servers</li>
      <li>Any activity that violates laws or public order</li>
    </ul>

    <h2>6. Disclaimers</h2>
    <ul>
      <li>This service is provided "AS IS" without warranties of any kind.</li>
      <li>The accuracy of location and HealthKit data depends on device hardware and Apple frameworks.</li>
      <li>The operator is not liable for service interruptions, data loss, or delayed reports.</li>
    </ul>

    <h2>7. Changes to These Terms</h2>
    <p>We may update these terms. Continued use after changes constitutes acceptance.</p>

    <h2>8. Contact</h2>
    <p>AICU Inc.<br>
    Email: <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a></p>
    `;
  }

  // Default: Japanese
  return `
    <h1>iOSアプリ利用規約</h1>
    <p>最終更新日: 2026年4月11日</p>

    <h2>1. サービス説明</h2>
    <p>nehan.aiはiOS用ライフログ記録アプリケーションです。位置情報・HealthKitデータ・メモを記録し、オンデバイスAIで日報を自動生成します。</p>

    <h2>2. データ収集</h2>
    <ul>
      <li><strong>位置情報</strong>: バックグラウンドでの位置追跡および逆ジオコーディングによる地名の記録。利用にはユーザーの明示的な許可が必要です。</li>
      <li><strong>HealthKitデータ</strong>: 睡眠分析・歩数・心拍数・マインドフルネス等の健康データ。すべてのデータ処理はデバイス上で行われます。利用にはユーザーの明示的な許可が必要です。</li>
      <li><strong>ユーザー入力</strong>: メモ・夢日記・ブログコンテンツ等のユーザーが作成したコンテンツ。</li>
    </ul>

    <h2>3. オンデバイスAI</h2>
    <p>テキスト生成にはApple Intelligence（Foundation Models）、画像生成にはImage Playgroundを使用します。すべてのAI処理はデバイス上で実行され、外部AIサービスにデータが送信されることはありません。</p>

    <h2>4. データ同期</h2>
    <p>データはHTTPSを通じてサーバー（Cloudflare Workers）にバックアップおよびブログ公開のために送信されます。詳細は<a href="/terms/privacy/ja">プライバシーポリシー</a>をご参照ください。</p>

    <h2>5. 禁止事項</h2>
    <ul>
      <li>APIの不正利用・逆コンパイル・リバースエンジニアリング</li>
      <li>他者のアカウントやトークンの不正使用</li>
      <li>サーバーへの過度な負荷をかける行為</li>
      <li>法令または公序良俗に反する行為</li>
    </ul>

    <h2>6. 免責事項</h2>
    <ul>
      <li>本サービスは「現状有姿」で提供され、いかなる保証もありません。</li>
      <li>位置情報およびHealthKitデータの正確性は、デバイスのハードウェアおよびAppleフレームワークに依存します。</li>
      <li>運営者はサービスの中断・データ損失・日報の遅延について責任を負いません。</li>
    </ul>

    <h2>7. 規約の変更</h2>
    <p>本規約は変更されることがあります。変更後もサービスを継続利用した場合、変更に同意したものとみなします。</p>

    <h2>8. お問い合わせ</h2>
    <p>AICU Inc.<br>
    メール: <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a></p>
  `;
}

export function serviceToSContent(lang: string): string {
  if (lang === 'en') {
    return `
    <h1>nehan.ai Terms of Service</h1>
    <p>Last updated: April 11, 2026</p>
    <p>These Terms of Service ("Terms") govern your use of nehan.ai (the "Service") operated by AICU Inc. ("we", "us", "AICU Inc."). By accessing or using the Service, you agree to be bound by these Terms.</p>

    <h2>1. Definitions</h2>
    <ul>
      <li><strong>"Service"</strong> means the nehan.ai life log recording, blog publishing, and related services accessible via the iOS application and website.</li>
      <li><strong>"User"</strong> means any individual who accesses or uses the Service.</li>
      <li><strong>"Content"</strong> means text, images, data, and other materials created, uploaded, or published through the Service.</li>
      <li><strong>"Account"</strong> means a registered user account on the Service.</li>
    </ul>

    <h2>2. Who Can Use the Service</h2>
    <ul>
      <li>You must be at least 13 years old to use the Service.</li>
      <li>If you are under 18 and reside in Japan, you must have parental or guardian consent to use the Service.</li>
      <li>By using the Service, you represent that you meet these eligibility requirements.</li>
    </ul>

    <h2>3. Your Account &amp; Responsibilities</h2>
    <ul>
      <li>Guest users (Tier 0) may use the app and sync data without registering.</li>
      <li>To publish blogs, you must register (Tier 1) by verifying your email address and choosing a username.</li>
      <li>Usernames must be 3-12 characters, lowercase alphanumeric with underscores and hyphens only.</li>
      <li>You are responsible for maintaining the security of your account credentials.</li>
      <li>You must not share your API key or allow unauthorized access to your account.</li>
    </ul>

    <h2>4. User Content on the Services</h2>
    <ul>
      <li>You are solely responsible for Content you create, upload, or publish through the Service.</li>
      <li>You represent that you have the right to publish any Content you submit.</li>
      <li>AICU Inc. reserves the right to remove Content that violates these Terms or applicable law.</li>
      <li>AICU Inc. is not obligated to monitor Content but may do so at its discretion.</li>
    </ul>

    <h2>5. Rights and Ownership</h2>
    <ul>
      <li>You retain all ownership rights in your Content.</li>
      <li>By publishing Content on the Service, you grant AICU Inc. a non-exclusive, royalty-free, worldwide license to display, distribute, and promote your Content within the Service.</li>
      <li>This license terminates when you delete your Content or Account, except for Content that has been shared or cached by third parties.</li>
    </ul>

    <h2>6. Prohibited Content &amp; Conduct</h2>
    <p>You agree not to:</p>
    <ul>
      <li>Post illegal content or content that promotes illegal activity</li>
      <li>Harass, bully, or threaten other users</li>
      <li>Impersonate any person or entity</li>
      <li>Post spam or engage in deceptive practices</li>
      <li>Abuse the API or attempt to circumvent rate limits or security measures</li>
      <li>Upload malware, viruses, or other harmful code</li>
      <li>Scrape or collect data from the Service without permission</li>
    </ul>

    <h2>7. DMCA / Takedown</h2>
    <p>If you believe your copyrighted work has been infringed on the Service, please send a written notice to <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a> including:</p>
    <ol>
      <li>Identification of the copyrighted work</li>
      <li>Identification of the infringing material and its location on the Service</li>
      <li>Your contact information</li>
      <li>A statement of good faith belief that the use is unauthorized</li>
      <li>A statement under penalty of perjury that the information is accurate</li>
      <li>Your physical or electronic signature</li>
    </ol>

    <h2>8. Termination &amp; Account Deletion</h2>
    <ul>
      <li>You may delete your account at any time through the app settings.</li>
      <li>Upon account deletion, we will delete all your data within 30 days.</li>
      <li>AICU Inc. may suspend or terminate accounts that violate these Terms.</li>
      <li>Sections 5, 9, 10, and 11 survive termination.</li>
    </ul>

    <h2>9. Disclaimers &amp; Limitation of Liability</h2>
    <ul>
      <li>THE SERVICE IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED.</li>
      <li>AICU INC. DOES NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, SECURE, OR ERROR-FREE.</li>
      <li>IN NO EVENT SHALL AICU INC.'S TOTAL LIABILITY EXCEED THE GREATER OF THE AMOUNT YOU PAID IN THE PAST 12 MONTHS OR $50 USD.</li>
      <li>AICU INC. SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES.</li>
    </ul>

    <h2>10. Resolving Disputes; Binding Arbitration</h2>
    <ul>
      <li>Any dispute arising from these Terms shall be resolved through binding arbitration administered by JAMS in Delaware, USA.</li>
      <li>Arbitration shall be conducted on an individual basis only. Class actions and class arbitrations are not permitted.</li>
      <li>You may opt out of arbitration by sending written notice to <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a> within 30 days of accepting these Terms.</li>
      <li>Claims that qualify for small claims court may be brought there instead of arbitration.</li>
    </ul>

    <h2>11. Governing Law and Venue</h2>
    <p>These Terms are governed by the laws of the State of Delaware, USA. Any disputes not subject to arbitration shall be resolved in the state or federal courts located in Delaware.</p>

    <h2>12. Amendments</h2>
    <p>We may update these Terms from time to time. We will notify registered users of material changes via email. Continued use after changes take effect constitutes acceptance.</p>

    <h2>13. General &amp; Contact</h2>
    <p>AICU Inc.<br>
    8 THE GREEN STE B<br>
    DOVER, DE 19901<br>
    Email: <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a></p>
    `;
  }

  // Default: Japanese
  return `
    <h1>nehan.ai 利用規約</h1>
    <p>最終更新日: 2026年4月11日</p>
    <p>本利用規約（以下「本規約」）は、AICU Inc.（以下「当社」）が提供するnehan.ai（以下「本サービス」）の利用条件を定めるものです。本サービスにアクセスまたは利用することにより、本規約に同意したものとみなされます。</p>

    <h2>1. 定義</h2>
    <ul>
      <li><strong>「本サービス」</strong>とは、nehan.aiのライフログ記録・ブログ公開・関連サービスを指し、iOSアプリケーションおよびウェブサイトからアクセス可能なサービスの総称です。</li>
      <li><strong>「ユーザー」</strong>とは、本サービスにアクセスまたは利用するすべての個人を指します。</li>
      <li><strong>「コンテンツ」</strong>とは、本サービスを通じて作成・アップロード・公開されたテキスト・画像・データその他の素材を指します。</li>
      <li><strong>「アカウント」</strong>とは、本サービス上の登録ユーザーアカウントを指します。</li>
    </ul>

    <h2>2. 利用資格</h2>
    <ul>
      <li>本サービスを利用するには13歳以上である必要があります。</li>
      <li>日本居住の18歳未満の方は、保護者の同意が必要です（民法第5条）。</li>
      <li>本サービスを利用することにより、上記の資格要件を満たしていることを表明します。</li>
    </ul>

    <h2>3. アカウントと責任</h2>
    <ul>
      <li>ゲストユーザー（Tier 0）は、登録なしでアプリの利用およびデータ同期が可能です。</li>
      <li>ブログを公開するには、メール認証およびユーザー名選択によるユーザー登録（Tier 1）が必要です。</li>
      <li>ユーザー名は3〜12文字の半角英小文字・数字・アンダースコア・ハイフンのみ使用可能です。</li>
      <li>アカウント認証情報のセキュリティ管理はユーザーの責任です。</li>
      <li>APIキーの共有や不正アクセスの許可は禁止されています。</li>
    </ul>

    <h2>4. ユーザーコンテンツ</h2>
    <ul>
      <li>本サービスを通じて作成・アップロード・公開するコンテンツについては、ユーザーが全責任を負います。</li>
      <li>投稿するコンテンツの公開権限を有していることをユーザーが表明するものとします。</li>
      <li>当社は本規約または適用法に違反するコンテンツを削除する権利を留保します。</li>
      <li>当社にはコンテンツを監視する義務はありませんが、裁量により監視を行う場合があります。</li>
    </ul>

    <h2>5. 権利と所有権</h2>
    <ul>
      <li>ユーザーはコンテンツに対するすべての所有権を保持します。</li>
      <li>コンテンツを本サービス上で公開することにより、当社に対し、本サービス内でコンテンツを表示・配信・宣伝するための非独占的・無償・世界的なライセンスを付与します。</li>
      <li>このライセンスは、コンテンツまたはアカウントを削除した時点で終了します。ただし、第三者によって共有またはキャッシュされたコンテンツは除きます。</li>
    </ul>

    <h2>6. 禁止コンテンツおよび禁止行為</h2>
    <p>以下の行為を禁止します：</p>
    <ul>
      <li>違法なコンテンツの投稿または違法行為を促進するコンテンツの投稿</li>
      <li>他のユーザーへの嫌がらせ・いじめ・脅迫</li>
      <li>他の個人または団体へのなりすまし</li>
      <li>スパムの投稿または欺瞞的行為</li>
      <li>APIの不正利用、レート制限やセキュリティ措置の回避</li>
      <li>マルウェア・ウイルス等の有害なコードのアップロード</li>
      <li>許可のない本サービスからのデータ収集・スクレイピング</li>
    </ul>

    <h2>7. 著作権侵害通知（DMCA）</h2>
    <p>本サービス上で著作権が侵害されていると思われる場合は、以下の情報を含む書面を <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a> までお送りください：</p>
    <ol>
      <li>著作権のある著作物の特定</li>
      <li>侵害と思われるコンテンツおよびその所在の特定</li>
      <li>お客様の連絡先情報</li>
      <li>当該利用が無許可であるという誠実な信念の声明</li>
      <li>情報が正確であるという偽証罪の制裁の下での声明</li>
      <li>お客様の物理的または電子的署名</li>
    </ol>

    <h2>8. 解約とアカウント削除</h2>
    <ul>
      <li>ユーザーはアプリの設定からいつでもアカウントを削除できます。</li>
      <li>アカウント削除後、30日以内にすべてのデータを削除します。</li>
      <li>当社は本規約に違反するアカウントを一時停止または終了する場合があります。</li>
      <li>第5条、第9条、第10条、第11条は解約後も有効です。</li>
    </ul>

    <h2>9. 免責事項および責任制限</h2>
    <ul>
      <li>本サービスは「現状有姿」で提供され、明示または黙示を問わず、いかなる保証もありません。</li>
      <li>当社は本サービスが中断なく、安全に、またはエラーなく動作することを保証しません。</li>
      <li>当社の責任総額は、過去12ヶ月間にお客様が支払った金額または50米ドルのいずれか大きい方を上限とします。</li>
      <li>当社は間接的・付随的・特別・結果的・懲罰的損害について責任を負いません。</li>
    </ul>

    <h2>10. 紛争解決・拘束力ある仲裁</h2>
    <ul>
      <li>本規約に起因する紛争は、米国デラウェア州においてJAMSが管理する拘束力ある仲裁により解決されます。</li>
      <li>仲裁は個人ベースでのみ行われます。クラスアクションおよび集団仲裁は認められません。</li>
      <li>本規約への同意から30日以内に <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a> に書面で通知することにより、仲裁をオプトアウトできます。</li>
      <li>少額裁判所の管轄に該当する請求は、仲裁の代わりに少額裁判所に提起できます。</li>
    </ul>
    <p><strong>日本居住者向け補足：</strong>消費者契約法に基づき、上記の仲裁条項が適用されない場合があります。日本居住者の消費者紛争については、東京地方裁判所を第一審の管轄裁判所とすることができます。</p>

    <h2>11. 準拠法および裁判管轄</h2>
    <p>本規約は米国デラウェア州法に準拠します。仲裁の対象とならない紛争は、デラウェア州の州裁判所または連邦裁判所で解決されるものとします。</p>
    <p><strong>日本居住者向け補足：</strong>日英両版の規約に矛盾がある場合は、日本居住者には日本語版が優先適用されます。電気通信事業法および特定商取引法に基づく表記は別途掲載します。</p>

    <h2>12. 規約の変更</h2>
    <p>当社は本規約を随時更新する場合があります。重要な変更については、登録ユーザーにメールで通知します。変更が有効になった後も本サービスを継続利用した場合、変更に同意したものとみなされます。</p>

    <h2>13. 一般条項・お問い合わせ</h2>
    <p>AICU Inc.<br>
    8 THE GREEN STE B<br>
    DOVER, DE 19901<br>
    メール: <a href="mailto:nehan@aicu.ai">nehan@aicu.ai</a></p>

    <h2>特定商取引法に基づく表記</h2>
    <table style="width:100%;border-collapse:collapse;margin-top:1rem;">
      <tr><td style="padding:8px;border:1px solid #ddd;font-weight:bold;">販売事業者</td><td style="padding:8px;border:1px solid #ddd;">AICU Inc.</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;font-weight:bold;">所在地</td><td style="padding:8px;border:1px solid #ddd;">8 THE GREEN STE B, DOVER, DE 19901, USA</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;font-weight:bold;">連絡先</td><td style="padding:8px;border:1px solid #ddd;">nehan@aicu.ai</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;font-weight:bold;">販売価格</td><td style="padding:8px;border:1px solid #ddd;">無料（将来有料プランを提供する可能性があります）</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;font-weight:bold;">支払方法</td><td style="padding:8px;border:1px solid #ddd;">現在無料のため該当なし</td></tr>
      <tr><td style="padding:8px;border:1px solid #ddd;font-weight:bold;">返品・キャンセル</td><td style="padding:8px;border:1px solid #ddd;">アカウントはいつでも削除可能です</td></tr>
    </table>
  `;
}
