import os
import sys
from pathlib import Path

DEPS = Path(__file__).resolve().parents[1] / "tmp" / "pdf_deps"
sys.path.insert(0, str(DEPS))

import arabic_reshaper
from bidi.algorithm import get_display
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output" / "pdf" / "sync_notifications_google_auth_detailed_diagnosis_ar.pdf"
OUT.parent.mkdir(parents=True, exist_ok=True)

FONT = r"C:\Windows\Fonts\arial.ttf"
FONT_BOLD = r"C:\Windows\Fonts\arialbd.ttf"
pdfmetrics.registerFont(TTFont("Arabic", FONT))
pdfmetrics.registerFont(TTFont("ArabicBold", FONT_BOLD))


def rtl(value):
    text = str(value)
    if not text:
        return ""
    return get_display(arabic_reshaper.reshape(text), base_dir="R")


PAGE_W, PAGE_H = A4
NAVY = colors.HexColor("#10233F")
BLUE = colors.HexColor("#1967B3")
CYAN = colors.HexColor("#15A6A6")
RED = colors.HexColor("#C73535")
ORANGE = colors.HexColor("#E68024")
GREEN = colors.HexColor("#23885B")
INK = colors.HexColor("#1D2939")
MUTED = colors.HexColor("#667085")
PALE = colors.HexColor("#F3F6FA")
LINE = colors.HexColor("#D8E0EA")

styles = getSampleStyleSheet()
BODY = ParagraphStyle(
    "ArabicBody",
    fontName="Arabic",
    fontSize=10.4,
    leading=17,
    alignment=TA_RIGHT,
    textColor=INK,
    wordWrap="RTL",
    spaceAfter=5,
)
SMALL = ParagraphStyle(
    "ArabicSmall",
    parent=BODY,
    fontSize=8.4,
    leading=13,
    textColor=MUTED,
)
H1 = ParagraphStyle(
    "ArabicH1",
    fontName="ArabicBold",
    fontSize=19,
    leading=27,
    alignment=TA_RIGHT,
    textColor=NAVY,
    wordWrap="RTL",
    spaceBefore=10,
    spaceAfter=9,
)
H2 = ParagraphStyle(
    "ArabicH2",
    fontName="ArabicBold",
    fontSize=14,
    leading=21,
    alignment=TA_RIGHT,
    textColor=BLUE,
    wordWrap="RTL",
    spaceBefore=8,
    spaceAfter=6,
)
H3 = ParagraphStyle(
    "ArabicH3",
    fontName="ArabicBold",
    fontSize=11.5,
    leading=18,
    alignment=TA_RIGHT,
    textColor=NAVY,
    wordWrap="RTL",
    spaceBefore=6,
    spaceAfter=4,
)
CENTER = ParagraphStyle(
    "ArabicCenter",
    parent=BODY,
    alignment=TA_CENTER,
)
CODE = ParagraphStyle(
    "Code",
    fontName="Courier",
    fontSize=7.5,
    leading=11,
    alignment=TA_LEFT,
    textColor=colors.HexColor("#24364B"),
    backColor=colors.HexColor("#EEF2F7"),
    borderPadding=7,
    borderColor=LINE,
    borderWidth=0.5,
)


def p(text, style=BODY):
    return Paragraph(rtl(text), style)


def h1(text):
    return Paragraph(rtl(text), H1)


def h2(text):
    return Paragraph(rtl(text), H2)


def h3(text):
    return Paragraph(rtl(text), H3)


def bullet(text, color=BLUE):
    dot = Paragraph("●", ParagraphStyle("dot", fontName="Helvetica-Bold", fontSize=7, textColor=color, alignment=TA_CENTER))
    t = Table([[p(text), dot]], colWidths=[159*mm, 6*mm])
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
    ]))
    return t


def note(title, text, color=BLUE):
    box = Table([[p(title, H3)], [p(text)]], colWidths=[165*mm])
    box.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.Color(color.red, color.green, color.blue, alpha=0.10)),
        ("BOX", (0, 0), (-1, -1), 1, color),
        ("LINEBEFORE", (0, 0), (0, -1), 4, color),
        ("LEFTPADDING", (0, 0), (-1, -1), 9),
        ("RIGHTPADDING", (0, 0), (-1, -1), 9),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return box


def audit_table(headers, rows, widths=None, severity_col=None):
    data = [[p(x, ParagraphStyle("th", parent=SMALL, fontName="ArabicBold", textColor=colors.white, alignment=TA_CENTER)) for x in headers]]
    for row in rows:
        data.append([p(x, SMALL) for x in row])
    if widths is None:
        widths = [165*mm/len(headers)] * len(headers)
    table = Table(data, colWidths=widths, repeatRows=1, hAlign="RIGHT")
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("GRID", (0, 0), (-1, -1), 0.45, LINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    for i in range(1, len(data)):
        commands.append(("BACKGROUND", (0, i), (-1, i), colors.white if i % 2 else PALE))
    if severity_col is not None:
        for i, row in enumerate(rows, start=1):
            raw = str(row[severity_col])
            c = RED if "حرج" in raw else ORANGE if "عال" in raw else GREEN if "منخفض" in raw else BLUE
            commands.append(("BACKGROUND", (severity_col, i), (severity_col, i), colors.Color(c.red, c.green, c.blue, alpha=0.12)))
    table.setStyle(TableStyle(commands))
    return table


class AuditDoc(BaseDocTemplate):
    def __init__(self, filename):
        super().__init__(
            filename,
            pagesize=A4,
            rightMargin=22*mm,
            leftMargin=22*mm,
            topMargin=22*mm,
            bottomMargin=20*mm,
            title="Detailed diagnosis of synchronization, notifications and Google sign-in",
            author="Codex",
        )
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="normal")
        self.addPageTemplates(PageTemplate(id="audit", frames=frame, onPage=self._page))

    def _page(self, canvas, doc):
        canvas.saveState()
        canvas.setFillColor(NAVY)
        canvas.rect(0, PAGE_H-10*mm, PAGE_W, 10*mm, fill=1, stroke=0)
        canvas.setFont("Arabic", 8)
        canvas.setFillColor(colors.white)
        canvas.drawRightString(PAGE_W-20*mm, PAGE_H-6.5*mm, rtl("تدقيق المزامنة والإشعارات وتسجيل Google"))
        canvas.setStrokeColor(LINE)
        canvas.line(20*mm, 14*mm, PAGE_W-20*mm, 14*mm)
        canvas.setFillColor(MUTED)
        canvas.setFont("Arabic", 8)
        canvas.drawRightString(PAGE_W-20*mm, 9*mm, rtl(f"الصفحة {doc.page}"))
        canvas.drawString(20*mm, 9*mm, "ERP Alum - Technical Audit")
        canvas.restoreState()


story = []

# Cover
story += [Spacer(1, 22*mm)]
story.append(Paragraph(rtl("التشخيص التفصيلي الشامل"), ParagraphStyle("cover1", parent=H1, fontSize=26, leading=36, alignment=TA_CENTER, textColor=NAVY)))
story.append(Paragraph(rtl("للمزامنة والإشعارات وتسجيل الدخول عبر Google"), ParagraphStyle("cover2", parent=H1, fontSize=21, leading=31, alignment=TA_CENTER, textColor=BLUE)))
story.append(Spacer(1, 9*mm))
story.append(Table([["SUPABASE", "FCM", "GOOGLE AUTH", "SQLITE"]], colWidths=[41*mm]*4, style=TableStyle([
    ("BACKGROUND", (0, 0), (-1, -1), NAVY), ("TEXTCOLOR", (0, 0), (-1, -1), colors.white),
    ("FONTNAME", (0, 0), (-1, -1), "Helvetica-Bold"), ("FONTSIZE", (0, 0), (-1, -1), 9),
    ("ALIGN", (0, 0), (-1, -1), "CENTER"), ("TOPPADDING", (0, 0), (-1, -1), 10),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 10), ("GRID", (0, 0), (-1, -1), 0.5, colors.white),
])))
story.append(Spacer(1, 14*mm))
story.append(p("مراجعة مستقلة للكود الحالي، ومسارات البيانات، وإدارة الجلسة، والصلاحيات، والعمل دون اتصال، ووصول الإشعارات في المقدمة والخلفية، وتسجيل Google على الهاتف وWindows.", CENTER))
story.append(Spacer(1, 8*mm))
story.append(note("حدود الدقة", "هذا التقرير يثبت ما يمكن إثباته من الكود وملفات SQL وإعدادات المنصات. لا يمكن تأكيد إعدادات Google Cloud وSupabase Dashboard وFirebase Console والأسرار المنشورة فعليًا دون الدخول إلى تلك اللوحات وإجراء اختبارات شبكة وحسابات حقيقية.", ORANGE))
story.append(Spacer(1, 14*mm))
story.append(p("تاريخ المراجعة: 17 أكتوبر 2026", CENTER))
story.append(p("النطاق: نسخة المشروع الموجودة محليًا وقت إعداد التقرير", CENTER))
story.append(PageBreak())

story.append(h1("1. الخلاصة التنفيذية"))
story.append(p("المنظومة ليست بدائية؛ فيها حلول جيدة مثل سجل تغييرات محلي، tombstones للحذف، server cursor، Realtime، رفع مجزأ، RLS، تسجيل token، وPKCE على Windows. لكن هذه الحلول تراكمت داخل طبقات كبيرة ومتداخلة، وأصبحت صعوبة فهم الحالة الحالية نفسها مصدر خطر."))
for text, color in [
    ("Supabase هو مصدر الهوية وعضوية الورشة والبيانات التشغيلية الحالي.", GREEN),
    ("SQLite هو مخزن العمل المحلي ومصدر تجربة offline-first.", BLUE),
    ("Firestore ما زال حاضرًا لمسارات النسخ القديمة والهجرة والتوافق، رغم أن Supabase أصبح المصدر الأساسي.", ORANGE),
    ("FCM مسؤول عن الوصول عندما يكون التطبيق في الخلفية أو مغلقًا، بينما Supabase Broadcast/Realtime يخدم التطبيق المفتوح.", BLUE),
    ("Google sign-in ليس مسارًا واحدًا: الهاتف يستخدم google_sign_in، وWindows يستخدم متصفحًا + loopback + Supabase OAuth، وله fallback مباشر يحتاج client secret.", ORANGE),
]:
    story.append(bullet(text, color))
story.append(Spacer(1, 4*mm))
story.append(audit_table(
    ["الحكم", "المجال", "المستوى"],
    [
        ["احتمال فقد أو استبدال تعديل متزامن ما زال قائمًا عند تعديل الصف نفسه offline من جهازين.", "حل التعارض", "حرج"],
        ["وجود Supabase + Firestore legacy + SQLite يزيد الفشل الجزئي وصعوبة التشخيص.", "معمارية المزامنة", "عالٍ"],
        ["وصول التطبيق المغلق يعتمد على سلسلة إعدادات خارج الكود بالكامل.", "الإشعارات الخلفية", "عالٍ"],
        ["هناك بريد إداري hard-coded كاستثناء في Edge Function.", "أمن الإشعارات", "حرج"],
        ["تضمين desktop client secret في تطبيق Windows ليس سرًا حقيقيًا وقابل للاستخراج.", "Google Windows", "حرج"],
        ["ملف تسجيل الدخول يقارب 3000 سطر ويمزج التسجيل والهجرة والورشة والواجهة.", "قابلية الصيانة", "عالٍ"],
        ["iOS Info.plist الظاهر لا يحتوي إعدادات URL schemes/notification background المعتادة.", "iOS", "عالٍ"],
    ],
    widths=[94*mm, 45*mm, 26*mm], severity_col=2,
))

story.append(h2("النتيجة الصريحة"))
story.append(note("الحكم", "المنظومة قابلة للعمل في الظروف العادية، لكنها ليست بعدُ منظومة مزامنة قابلة للتدقيق الكامل. أكبر نقص ليس غياب Realtime؛ بل غياب سجل عمليات مركزي قابل للمراجعة وحل تعارض محدد لكل نوع بيانات، مع اعتماد كبير على fallbacks صامتة وSharedPreferences لمعرفة الحالة.", RED))

story.append(h1("2. المعمارية الفعلية ومصادر الحقيقة"))
story.append(Paragraph("LOCAL SQLITE  ->  CHANGE LOG  ->  SUPABASE workshop_sync_rows<br/>"
                       "      ^                         |<br/>"
                       "      |---- Realtime / cursor -|<br/><br/>"
                       "SUPABASE AUTH -> workshop_members -> RLS / permissions<br/>"
                       "SUPABASE EDGE FUNCTION -> FCM -> device token -> notification<br/>"
                       "GOOGLE -> Supabase session -> workshop membership -> local context<br/>"
                       "FIRESTORE -> legacy backup / migration / fallback paths",
                       CODE))
story.append(h2("طبقات المزامنة"))
for x in [
    "قاعدة SQLite تحفظ بيانات العمل وتنتج pending cloud changes.",
    "SupabaseWorkshopSyncService يحول كل صف محلي إلى صف سحابي عام يحتوي table_name وrow_id وpayload وupdated_at وdeleted_at وdevice_id وrevision.",
    "Supabase Realtime يرسل اسم الصف المتغير، ثم يجلب التطبيق الصف ويطبقه محليًا.",
    "فحص خلفي بطيء كل ثلاث دقائق يصلح الأحداث التي ضاعت أثناء النوم أو انقطاع الشبكة.",
    "SupabaseCatalogSyncService يفصل الكتالوج العام عن بيانات الورشة، ويستخدم manifest وchunks.",
    "CloudSyncService ما زال طبقة تنسيق كبيرة تضم Supabase وFirestore والهجرة والنسخ والـ feedback.",
]: story.append(bullet(x))
story.append(h2("مصدر الحقيقة حسب المجال"))
story.append(audit_table(
    ["ملاحظة", "المصدر المقصود", "المجال"],
    [
        ["الجلسة الحالية في الكود مضبوطة على Supabase.", "Supabase Auth", "هوية المستخدم"],
        ["الدور والصلاحيات والحظر من workshop_members.", "Supabase", "عضوية الورشة"],
        ["تعديلات محلية أولًا ثم رفع ودمج.", "SQLite + Supabase rows", "بيانات الورشة"],
        ["منفصل عن أسعار وإعدادات الورشة.", "Supabase catalog manifest/chunks", "الكتالوج العام"],
        ["Supabase Preferences تحدد من يُستبعد في Edge Function.", "Supabase", "تفضيلات الإشعارات"],
        ["بقيت مسارات توافق ونسخ واسترجاع.", "Firestore legacy", "الإرث والهجرة"],
    ], widths=[73*mm, 48*mm, 44*mm]
))

story.append(PageBreak())
story.append(h1("3. التشخيص التفصيلي للمزامنة"))
story.append(h2("3.1 نقاط القوة المثبتة"))
for x in [
    "حماية pending local snapshot من أن يمسحه تنزيل remote قبل نجاح الرفع.",
    "رفع مجزأ بحجم 25 صفًا مع retries لتجنب statement timeout.",
    "تنزيل paginated، مع تقليل حجم batches للجداول الثقيلة.",
    "تسلسل عمليات التنزيل كي لا تتداخل imports مدمرة على SQLite.",
    "استخدام tombstones بدل نسيان الحذف.",
    "تمييز device_id لمنع إعادة تطبيق echo الخاص بالجهاز نفسه.",
    "server_updated_at cursor لمعالجة الساعة الخاطئة والتعديلات offline المتأخرة.",
    "revision dedupe لتقليل تطبيق الحدث نفسه مرتين.",
    "فصل الكتالوج العام عن بيانات وأسعار الورشة.",
    "RLS على workshop_sync_rows وعضوية الورشة.",
]: story.append(bullet(x, GREEN))

story.append(h2("3.2 P0 - حل التعارض ليس نموذجًا تجاريًا مكتملًا"))
story.append(p("النظام يستطيع الحفاظ على remote الأحدث في بعض عمليات الرفع، ويستخدم updated_at وrevision وserver_updated_at. لكن ذلك لا يساوي حل تعارض دلالي. إذا عدل جهازان الصف نفسه دون اتصال، فالنتيجة في الغالب نسخة صف كاملة تفوز على الأخرى وفق ترتيب زمني/رفع، وليس merge حقليًا ولا سجل عمليات."))
story.append(p("مثال: المدير يغير السعر على الهاتف، وفي الوقت نفسه العامل يغير حالة الطلب على الكمبيوتر. إذا كان الاثنان محفوظين داخل payload نفسه ولم تكن قواعد الدمج مخصصة لذلك الجدول، قد يفوز صف كامل ويعيد قيمة الحقل الآخر."))
story.append(note("المطلوب", "تعريف سياسة لكل جدول: append-only، last-write-wins، field merge، server-authoritative، أو transaction. الطلبات والمدفوعات والمخزون لا يجوز أن تشترك كلها في سياسة عامة واحدة.", RED))

story.append(h2("3.3 P0 - صفوف JSON كاملة تزيد مجال الخسارة"))
story.append(p("workshop_sync_rows يخزن payload كاملًا للصف المحلي. هذا يبسط النسخ، لكنه يجعل كل تعديل صغير يحمل نسخة كاملة وقد يستبدل تعديلًا مستقلًا في حقل آخر. كما يرفع حجم النقل ويجعل الفهرسة والتحقق على الخادم أضعف."))

story.append(h2("3.4 P1 - الاعتماد على ساعة الجهاز لم ينته تمامًا"))
story.append(p("إضافة server_updated_at خطوة صحيحة لإكمال cursor، لكن updated_at القادم من الجهاز ما زال يدخل في مقارنة الأحدث وحماية remote. الجهاز ذو الساعة الخاطئة يمكن أن ينتج ترتيبًا غير منطقي، خصوصًا في بيئات لا تطبق migration الخاصة بالـ server cursor."))

story.append(h2("3.5 P1 - طبقة CloudSyncService ضخمة جدًا"))
story.append(p("CloudSyncService يتجاوز 5100 سطر، وSupabaseWorkshopSyncService يتجاوز 2600 سطر. الطبقة الأولى تدير التهيئة، Firebase legacy، Supabase، health checks، listeners، backup chunks، leases، queues، feedback، restore والهجرة. هذا حجم ومسؤوليات تجعل إثبات صحة الحالات الانتقالية صعبًا."))
story.append(note("الخطر", "وجود comments دفاعية كثيرة مفيد، لكنه يكشف أن النظام يُصلح حوادث متتابعة داخل نفس الطبقة بدل فرض state machine صغيرة قابلة للاختبار.", ORANGE))

story.append(h2("3.6 P1 - مساران سحابيان وفشل جزئي"))
story.append(p("Supabase هو المسار الحالي، لكن Firestore بقي للتوافق والنسخ والهجرة. قد تنجح جلسة Supabase وتفشل Firebase، أو ينجح upload في مسار ويعلق restore في آخر. الرسائل المطبوعة والفallbacks قد تجعل المستخدم يرى نجاحًا جزئيًا دون صورة موحدة للحالة."))

story.append(h2("3.7 P1 - SharedPreferences تحمل حالة تشغيل حساسة"))
story.append(p("مؤشرات آخر sync وbootstrap وpending generations وworkshop identifiers موزعة في SharedPreferences. هي مناسبة للكاش، لكنها ليست سجلًا معاملاتيًا. انقطاع التطبيق بين كتابة SQLite وتحديث المؤشر قد يخلق حالة تحتاج repair pass."))

story.append(h2("3.8 P1 - الحذف يحتاج ضمانًا موحدًا"))
story.append(p("يوجد دعم tombstones في Supabase ومسارات قديمة منفصلة في Firestore لبعض الجداول. يجب إثبات أن كل جدول قابل للحذف يكتب tombstone، وأن retention لا يمسحه قبل وصول جهاز ظل offline مدة طويلة."))

story.append(h2("3.9 P1 - لا يظهر سجل تدقيق دائم للمزامنة"))
story.append(p("التشخيص يعتمد كثيرًا على debugPrint وملخصات أخيرة. لا يوجد ظاهرًا sync journal محلي دائم يسجل operation id، الجدول، الصف، الجهاز، المستخدم، hash قبل/بعد، المحاولة، والنتيجة. عند شكوى فقد بيانات، إعادة بناء ما حدث ستكون صعبة."))

story.append(h2("3.10 P2 - عرض الحالة للمستخدم غير كافٍ"))
for x in [
    "يلزم فصل: محفوظ محليًا، في انتظار الرفع، مرفوع، نزلت نسخة أحدث، تعارض يحتاج مراجعة، وفشل صلاحية.",
    "زر المزامنة اليدوي يجب أن يعرض counts ووقت آخر نجاح وخطأ actionable، لا spinner طويل فقط.",
    "يجب ألا يعني انتهاء progress أن كل الجداول تأكدت من الخادم.",
]: story.append(bullet(x))

story.append(PageBreak())
story.append(h1("4. سيناريوهات الفشل في المزامنة"))
story.append(audit_table(
    ["الإجراء المقترح", "النتيجة المحتملة", "السيناريو"],
    [
        ["اختبار جهازين وحل تعارض لكل جدول.", "صف كامل قد يفوز ويستبدل جزءًا من الآخر.", "تعديل الصف نفسه offline من جهازين"],
        ["ضمان server cursor migration وbootstrap كامل.", "قد يفوّت الجهاز الصف إن اعتمد على وقت العميل.", "ساعة جهاز متأخرة"],
        ["تأكيد ack ذري وربط operation id.", "يعاد الرفع؛ غالبًا آمن مع upsert لكن الإشعار قد يتكرر.", "انقطاع بعد رفع السحابة وقبل ack المحلي"],
        ["منع overwrite وتنفيذ publish-before-download دائمًا.", "قد يختلط remote مع pending local.", "ضغط تنزيل والأسطر المحلية غير مرفوعة"],
        ["retain tombstones حسب آخر seen لكل جهاز أو مدة طويلة.", "السجل المحذوف يعود من جهاز قديم.", "جهاز offline طويلًا بعد الحذف"],
        ["transaction/version موحد للكتالوج والإعدادات التابعة.", "مقاطع جديدة مع قواعد/أسعار قديمة مؤقتًا.", "تحديث كتالوج متعدد الجداول"],
        ["فصل واضح وإزالة fallback القديم بعد الهجرة.", "حالة نجاح جزئي ورسائل مربكة.", "Supabase يعمل وFirebase يفشل"],
        ["health dashboard وrepair command.", "الحساب يعمل محليًا دون أن يعرف المستخدم أن الأجهزة الأخرى قديمة.", "Realtime متوقف والفحص الدوري يفشل"],
    ], widths=[60*mm, 55*mm, 50*mm]
))

story.append(h1("5. التشخيص التفصيلي للإشعارات"))
story.append(h2("5.1 يوجد مساران مختلفان"))
story.append(audit_table(
    ["الحد", "يعمل متى؟", "المسار"],
    [
        ["لا يوقظ التطبيق المغلق؛ يعتمد على اتصال Realtime.", "التطبيق مفتوح ومتصّل", "Supabase Broadcast + local notification"],
        ["يتطلب token وEdge Function وFirebase service account وإعداد المنصة.", "الخلفية أو التطبيق مغلق", "FCM push"],
        ["قد يكرر المسارين إن فشل dedupe.", "بعد تنزيل صف جديد", "Sync fallback notification"],
    ], widths=[66*mm, 50*mm, 49*mm]
))

story.append(h2("5.2 نقاط القوة"))
for x in [
    "قناة Android ذات importance max وصوت واهتزاز.",
    "طلب صلاحية الإشعارات على Android وDarwin.",
    "تسجيل FCM token وإعادة تسجيله عند refresh وعند تغير جلسة Supabase.",
    "RPC ينقل token بأمان نسبيًا عندما يتغير الحساب على الجهاز نفسه.",
    "Edge Function تتحقق من المستخدم والعضوية والحظر والصلاحية.",
    "تفضيلات المستخدم تُطبق على الخادم قبل الإرسال.",
    "تنظيف tokens غير المسجلة عند رد FCM بـ UNREGISTERED.",
    "استبعاد مرسل الحدث من المستلمين.",
]: story.append(bullet(x, GREEN))

story.append(h2("5.3 P0 - استثناء إداري hard-coded في الخادم"))
story.append(p("Edge Function تعتبر مستخدمًا admin إن وجد في app_admins أو إذا طابق بريدًا ثابتًا داخل الكود. هذا باب صلاحية غير مركزي، وغير قابل للتدقيق من قاعدة البيانات وحدها، ويصعب تدويره عند تغير المالك."))
story.append(note("الإصلاح", "إزالة البريد من Edge Function نهائيًا. الإدارة يجب أن تأتي من app_admins أو claim موقّع ومدار بإجراء رسمي مع audit log.", RED))

story.append(h2("5.4 P1 - dedupe ضعيف نسبيًا"))
story.append(p("الإشعارات المحلية تستخدم مفتاحًا من orderCode + new/edit ونافذة 25 ثانية. FCM يرسل event_id لكنه لا يظهر أن كل مسارات العرض تستخدمه مفتاحًا دائمًا. تعديلان مشروعان للطلب نفسه خلال 25 ثانية قد يُخفى أحدهما، أو قد يتكرر حدث بعد انتهاء النافذة."))

story.append(h2("5.5 P1 - background handler لا يطبق منطق التطبيق"))
story.append(p("معالج FCM في الخلفية يهيئ Firebase فقط. عند وصول notification payload يتولى النظام العرض، لكن data-only أو احتياجات مزامنة فورية لن تُعالج بالكامل في isolate. يجب توثيق أنواع payload التي تعتمد على notification مقابل data."))

story.append(h2("5.6 P1 - Windows لا يدعم push الحقيقي"))
story.append(p("WorkerPushNotificationService يعتبر Android/iOS/macOS/Web مدعومة ولا يضم Windows. على Windows يبقى Realtime/local notification داخل التطبيق، لكن لا يوجد FCM desktop native عندما يكون التطبيق مغلقًا."))

story.append(h2("5.7 P1 - إعداد iOS غير مكتمل في الملفات الظاهرة"))
story.append(p("Info.plist الظاهر لا يحتوي UIBackgroundModes remote-notification ولا URL scheme الخاص بـ Google. قد تضيفها ملفات build أخرى أو Xcode capabilities، لكن من الكود المراجع لا يمكن إثبات جاهزية iOS. كما يلزم APNs key وربطه بـ Firebase."))

story.append(h2("5.8 P1 - إعدادات المنصة الخارجية نقطة فشل صامتة"))
for x in [
    "FIREBASE_SERVICE_ACCOUNT_JSON يجب أن يكون JSON كاملًا داخل أسرار Supabase Edge Functions.",
    "FCM API v1 يجب أن تكون مفعلة والمشروع مطابقًا لـ firebase_options.",
    "APNs key/certificate مطلوب لـ iOS.",
    "Web push يحتاج VAPID/config وservice worker صحيحًا.",
    "قناة Android لا يمكن تخفيض/تغيير بعض خصائصها بعد إنشائها إلا بتغيير id أو إعدادات النظام.",
]: story.append(bullet(x, ORANGE))

story.append(h2("5.9 P2 - صفحة الإعدادات تخفي الأخطاء"))
story.append(p("عند فشل حفظ preference تعكس الصفحة المفتاح إلى حالته السابقة دون رسالة للمستخدم. كذلك تعتمد role المخزنة في SharedPreferences لتحديد الخيارات، بينما مصدر الدور الحقيقي Supabase. إذا تأخر تحديث الكاش قد تظهر مجموعة إعدادات خاطئة."))

story.append(h2("5.10 P2 - لا يوجد inbox داخل التطبيق"))
story.append(p("الإشعار لحظي فقط. لا يظهر سجل مركزي للأحداث المقروءة وغير المقروءة. إذا فُقد push أو ضغطه المستخدم بالخطأ، لا توجد قائمة يرجع إليها."))

story.append(PageBreak())
story.append(h1("6. سلسلة وصول الإشعار وتشخيصها"))
story.append(audit_table(
    ["علامة الفشل", "نقطة التحقق", "المرحلة"],
    [
        ["لا row في device_push_tokens.", "صلاحية الإشعار + getToken + workshop UUID.", "تسجيل الجهاز"],
        ["403 من Edge Function.", "عضوية المرسل، blocked، role/permission.", "السماح بالإرسال"],
        ["sent=0 بلا failed.", "المستلمون، preferences، tokens، استبعاد المرسل.", "اختيار الجمهور"],
        ["500 ورسالة service account.", "سر FIREBASE_SERVICE_ACCOUNT_JSON.", "اعتماد FCM"],
        ["UNREGISTERED.", "التطبيق محذوف أو token منتهي؛ يُحذف الصف.", "إرسال FCM"],
        ["يصل push ولا يفتح الصفحة.", "data payload، pending handler، order_id/type.", "التنقل بعد الضغط"],
        ["يصل مرتين.", "Realtime + FCM + sync fallback وevent_id.", "منع التكرار"],
        ["لا يصل والتطبيق مغلق على Windows.", "غير مدعوم في الخدمة الحالية.", "حد المنصة"],
    ], widths=[55*mm, 65*mm, 45*mm]
))

story.append(h1("7. التشخيص التفصيلي لتسجيل الدخول عبر Google"))
story.append(h2("7.1 المسارات الحالية"))
story.append(audit_table(
    ["المآخذ", "المسار", "المنصة"],
    [
        ["يعتمد على serverClientId وتكوين SHA/Google project.", "google_sign_in -> idToken -> Supabase signInWithIdToken", "Android/iOS/macOS"],
        ["يعتمد على دعم الويب والredirects.", "plugin/web OAuth -> Supabase", "Web"],
        ["loopback ports + browser + Supabase redirect.", "Supabase OAuth عبر متصفح النظام", "Windows أساسي"],
        ["يتطلب client secret داخل build؛ غير مناسب كسر.", "Google Authorization Code + PKCE + token endpoint", "Windows fallback مباشر"],
    ], widths=[68*mm, 64*mm, 33*mm]
))

story.append(h2("7.2 نقاط القوة"))
for x in [
    "Supabase هو auth gate النهائي بدل الاحتفاظ بجلسة Firebase مزدوجة.",
    "التحقق من عضوية الورشة بعد الدخول قبل نشر الجلسة للواجهة.",
    "وجود signup admission hook وإزالة الحساب اليتيم عند فشل الربط.",
    "Windows loopback يستخدم state عشوائي وPKCE S256 في المسار المباشر.",
    "Random.secure مستخدم للقيم الحساسة.",
    "timeout واضح وتلخيص أخطاء المستخدم.",
    "sign-out المحلي يُنشر فورًا إلى auth gate قبل تنظيف الشبكة.",
]: story.append(bullet(x, GREEN))

story.append(h2("7.3 P0 - client secret داخل تطبيق سطح المكتب"))
story.append(p("المسار المباشر في Windows يقرأ GOOGLE_WINDOWS_OAUTH_CLIENT_SECRET من compile-time environment ويرسله إلى Google token endpoint. أي secret داخل تطبيق desktop قابل للاستخراج من binary أو الذاكرة؛ لا يمكن اعتباره سرًا موثوقًا."))
story.append(note("الإصلاح", "اعتمد مسار Supabase OAuth/PKCE الذي لا يحتاج secret في العميل، أو استخدم backend exchange. احذف fallback الذي يشترط client secret من النسخة الموزعة.", RED))

story.append(h2("7.4 P1 - تعقيد شديد وتكرار المسارات"))
story.append(p("login_screen.dart يقارب 3000 سطر ويحتوي تسجيل البريد، إنشاء الحساب، Google الحالي، Google legacy، هجرة Firebase، إنشاء الورشة، قبول العضوية، حذف المستخدم اليتيم، إصلاح الاسم، وحالات الواجهة. توجد دوال Google حالية وأخرى legacy طويلة. هذا يجعل تعديلًا صغيرًا قادرًا على كسر منصة أخرى."))

story.append(h2("7.5 P1 - قراءة email/name من JWT في العميل"))
story.append(p("الشاشة تفك idToken محليًا لاستخراج البريد والاسم قبل تمريره إلى Supabase. هذا مقبول للعرض أو تجهيز permit فقط إذا كان الخادم لا يثق بهذه القيمة دون تحقق. القرار الأمني النهائي يجب أن يعتمد على token المتحقق منه داخل Supabase hook، لا على payload فكها العميل دون signature verification."))

story.append(h2("7.6 P1 - loopback redirect configuration هش"))
story.append(p("Windows يجرب منافذ 53682 و53683 و53684 ثم منفذًا عشوائيًا. يجب أن تقبل إعدادات Supabase redirects هذه العناوين. النص يقترح wildcard loopback، لكن دعم wildcard وسياساته يجب تأكيده في Dashboard. Firewall أو برنامج آخر قد يمنع bind أو callback."))

story.append(h2("7.7 P1 - iOS configuration غير مثبتة"))
story.append(p("Info.plist المراجع لا يحتوي CFBundleURLTypes الخاص بـ reversed client id. قد يكون Google sign-in على iOS غير مكتمل ما لم تضفه Xcode أو ملف آخر."))

story.append(h2("7.8 P1 - server client ID ثابت في المصدر"))
story.append(p("معرف OAuth ليس سرًا، لذلك وجوده في الكود ليس ثغرة بحد ذاته. لكن ثباته يربط builds والبيئات بمشروع واحد، ويصعب فصل dev/staging/prod. يجب نقله إلى flavors أو dart-defines موثقة."))

story.append(h2("7.9 P1 - مزج استعادة كلمة المرور بين مزودين"))
story.append(p("AuthService يحاول Supabase ثم Firebase fallback في استعادة كلمة المرور والتحقق. قد يصل المستخدم إلى بريد من مزود لا يملك جلسته التشغيلية الحالية، أو تظهر رسالة مزود مختلف. يجب حصر Firebase fallback في حساب legacy معلوم لا في كل فشل Supabase."))

story.append(h2("7.10 P2 - sign-out لا يسحب كل الجلسات"))
story.append(p("Supabase signOut يستخدم scope محليًا لتجنب انتظار الشبكة. هذا جيد لتجربة المستخدم، لكنه لا يلغي refresh tokens على الأجهزة الأخرى. يجب أن يوجد خيار منفصل: خروج من هذا الجهاز، وخروج من جميع الأجهزة."))

story.append(PageBreak())
story.append(h1("8. الأمن والخصوصية"))
story.append(audit_table(
    ["الإجراء", "الملاحظة", "الدرجة"],
    [
        ["إزالة البريد والاعتماد على app_admins فقط.", "بريد إداري ثابت في Edge Function.", "حرج"],
        ["إلغاء secret من العميل واستخدام backend/Supabase OAuth.", "Google desktop secret داخل build.", "حرج"],
        ["مراجعة كل SECURITY DEFINER وSET search_path والمنح.", "عدد كبير من RPCs ذات صلاحيات مرتفعة.", "عالٍ"],
        ["تدوير الأسرار وعدم تسجيل tokens أو payload حساس.", "Edge Function تحمل service role وFirebase service account.", "عالٍ"],
        ["تشفير محلي أو secure storage لما هو حساس.", "SharedPreferences ليست مخزن أسرار.", "عالٍ"],
        ["تقليل البيانات في الإشعار وإتاحة وضع خاص.", "عنوان العميل ورقم الطلب قد يظهران على lock screen.", "متوسط"],
        ["Retention وaudit access واضحان.", "tokens/preferences والأحداث تحتاج سياسة احتفاظ.", "متوسط"],
    ], widths=[68*mm, 70*mm, 27*mm], severity_col=2
))
story.append(h2("RLS"))
story.append(p("وجود RLS وسياسات العضوية نقطة جيدة، لكن صحة الحماية تعتمد على تطبيق ملفات SQL فعليًا وبالترتيب الصحيح. وجود الملف في المستودع لا يثبت أن قاعدة الإنتاج حدثت. يلزم migration registry وجدول schema version وفحص startup إداري."))

story.append(h1("9. المراقبة والتشخيص الناقصان"))
for x in [
    "لا يوجد correlation ID موحد ينتقل من حفظ SQLite إلى Supabase row إلى FCM إلى notification tap.",
    "لا توجد شاشة صحة تعرض آخر upload/download وpending count وRealtime status وtoken registration.",
    "لا توجد telemetry مجمعة لمعدل فشل Edge Function أو عدد tokens الميتة.",
    "debugPrint لا يكفي للإنتاج ولا يحفظ سجلًا بعد إعادة التشغيل.",
    "لا توجد أداة export diagnostics من داخل التطبيق مع إخفاء الأسرار.",
]: story.append(bullet(x))

story.append(h1("10. الاختبارات الناقصة"))
story.append(h2("مزامنة"))
for x in [
    "جهازان يعدلان حقولًا مختلفة في الصف نفسه offline ثم يتصلان بترتيبين مختلفين.",
    "حذف offline ثم تعديل نفس الصف على جهاز آخر.",
    "انقطاع بعد server commit وقبل local acknowledgement.",
    "ساعة جهاز متقدمة أو متأخرة 24 ساعة.",
    "Realtime event مفقود ثم إصلاح health pass.",
    "full restore أثناء وجود pending local changes.",
    "تحديث catalog manifest يفشل في chunk الأوسط.",
    "مستخدم محظور أثناء وجود التطبيق مفتوحًا.",
]: story.append(bullet(x))
story.append(h2("إشعارات"))
for x in [
    "Foreground/background/terminated لكل Android وiOS/Web/macOS.",
    "تجديد token وتغيير الحساب على الجهاز نفسه.",
    "إلغاء preference ثم التأكد من عدم الإرسال على الخادم.",
    "إشعاران لنفس الطلب خلال أقل من 25 ثانية.",
    "الضغط قبل اكتمال تهيئة navigator والمزامنة.",
    "service account خطأ، APNs غير معد، وtoken UNREGISTERED.",
]: story.append(bullet(x))
story.append(h2("Google"))
for x in [
    "حساب جديد، موجود، بلا عضوية، محظور، وعضوية pending.",
    "إلغاء اختيار الحساب وtimeout وstate mismatch.",
    "Windows منافذ loopback الثلاثة مشغولة.",
    "تغيير الحساب Google مع session Supabase قديمة.",
    "Android release SHA-1/SHA-256 وليس debug فقط.",
    "iOS URL scheme وWeb redirect domains.",
    "فشل إنشاء العضوية بعد نجاح إنشاء auth user ثم cleanup.",
]: story.append(bullet(x))

story.append(PageBreak())
story.append(h1("11. خطة الإصلاح مرتبة"))
story.append(h2("P0 - قبل التوسع"))
for x in [
    "إزالة البريد الإداري الثابت من Edge Function.",
    "إزالة Google desktop client secret من التطبيق الموزع.",
    "اختبار صريح لتعارض تعديل نفس الصف من جهازين.",
    "إضافة sync operation journal دائم ومعرف correlation.",
    "فحص production migrations وRLS وserver cursor عند startup الإداري.",
]: story.append(bullet(x, RED))

story.append(h2("P1 - توحيد المنظومة"))
for x in [
    "تقليص CloudSyncService إلى orchestrator، وفصل legacy migration نهائيًا.",
    "تعريف سياسة تعارض لكل جدول وكتابة اختبارات property/integration لها.",
    "إنشاء SyncStatus موحد بدل عشرات flags وSharedPreferences keys.",
    "اعتماد event_id موحد لكل الإشعارات وdedupe دائم محدود الحجم.",
    "إكمال إعداد iOS وإثباته باختبار جهاز فعلي.",
    "فصل Google flow عن LoginScreen إلى controller/service لكل منصة.",
]: story.append(bullet(x, ORANGE))

story.append(h2("P2 - التشغيل والمراقبة"))
for x in [
    "شاشة صحة للمزامنة والإشعارات يمكن للمستخدم تصديرها.",
    "مقاييس Edge Function وFCM ومعدل فشل token.",
    "Inbox للأحداث المهمة مع حالة القراءة.",
    "زر إصلاح: إعادة تسجيل token، إعادة Realtime، وfull reconcile آمن.",
    "بيئات منفصلة dev/staging/prod وOAuth clients منفصلة.",
]: story.append(bullet(x))

story.append(h1("12. قائمة تحقق تشغيلية"))
checks = [
    "Supabase session صالحة والعضوية غير محظورة.",
    "workshop UUID يطابق العضوية والكاش المحلي.",
    "pending rows = 0 بعد المزامنة اليدوية.",
    "server_updated_at موجود ويُحدث من الخادم.",
    "Realtime channel subscribed بعد resume.",
    "RLS يمنع عضو ورشة من قراءة ورشة أخرى.",
    "FCM token موجود للمستخدم والورشة الحالية.",
    "Edge Function ترى service account صحيحًا.",
    "التفضيلات توقف الإرسال فعليًا.",
    "Android channel موجود والصلاحية ممنوحة.",
    "iOS APNs وbackground mode وURL scheme مختبرة.",
    "Google redirects لكل منصة مسجلة.",
    "Windows OAuth يعمل دون secret مضمّن.",
    "حساب بلا عضوية لا يدخل إلى بيانات الورشة.",
    "logout يمسح سياق الورشة والقنوات والـ token ownership حسب السياسة.",
]
for x in checks: story.append(bullet("□ " + x, CYAN))

story.append(h1("13. الحكم النهائي"))
story.append(p("المزامنة الحالية أقوى من نسخة backup/download بسيطة، وتحتوي معالجة واعية لمشاكل الساعة وRealtime والحذف والرفع الثقيل. لكن التعقيد أصبح عاليًا لدرجة أن الثقة لا يجب أن تأتي من كثرة الشيفرة، بل من اختبارات أجهزة متعددة وسجل عمليات قابل للتدقيق وسياسات تعارض صريحة."))
story.append(p("الإشعارات تعمل عبر تصميم هجين صحيح من حيث المبدأ: Realtime للمقدمة وFCM للخلفية. إلا أن سلسلة FCM فيها نقاط إعداد خارجية كثيرة، وWindows خارج التغطية عند إغلاق التطبيق، ومنع التكرار يحتاج event identity أقوى."))
story.append(p("تسجيل Google لديه أساس جيد، خصوصًا جعل Supabase مالك الجلسة ووجود PKCE/state على Windows. أخطر نقطة هي fallback الذي يتطلب client secret داخل تطبيق سطح المكتب؛ يجب إزالته. ثاني أخطر نقطة هي ضخامة login_screen وتداخل الهجرة والعضوية والواجهة داخله."))
story.append(note("الخلاصة النهائية", "الأولوية ليست إضافة مزيد من retries. الأولوية هي تقليل عدد المسارات، إزالة الامتيازات الثابتة والأسرار من العميل، تعريف التعارض، وبناء observability تجعل أي فقد أو فشل قابلًا للإثبات والتصحيح.", NAVY))

story.append(h1("14. الملفات التي شملتها المراجعة"))
for x in [
    "lib/services/cloud_sync_service.dart",
    "lib/services/supabase_workshop_sync_service.dart",
    "lib/services/supabase_catalog_sync_service.dart",
    "lib/services/order_notification_service.dart",
    "lib/services/worker_push_notification_service.dart",
    "lib/Screen/notification_settings_screen.dart",
    "lib/services/auth_service.dart",
    "lib/services/supabase_account_service.dart",
    "lib/services/windows_google_sign_in_io.dart",
    "lib/login_screen.dart",
    "lib/main.dart",
    "android/app/src/main/AndroidManifest.xml",
    "ios/Runner/Info.plist",
    "supabase/catalog_sync.sql",
    "supabase/push_notifications.sql",
    "supabase/functions/send-worker-assignment/index.ts",
]: story.append(bullet(x))

doc = AuditDoc(str(OUT))
doc.build(story)
print(OUT)
