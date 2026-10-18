import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tmp" / "pdf_deps"))

import arabic_reshaper
from bidi.algorithm import get_display
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

OUT = ROOT / "output" / "pdf" / "kit_caisson_tunnel_glass_tempered_detailed_audit_ar.pdf"
OUT.parent.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont("Arabic", r"C:\Windows\Fonts\arial.ttf"))
pdfmetrics.registerFont(TTFont("ArabicBold", r"C:\Windows\Fonts\arialbd.ttf"))

def rtl(x): return get_display(arabic_reshaper.reshape(str(x)), base_dir="R")

NAVY=colors.HexColor("#10233F"); BLUE=colors.HexColor("#1769AA"); RED=colors.HexColor("#C73535")
ORANGE=colors.HexColor("#E68024"); GREEN=colors.HexColor("#23885B"); INK=colors.HexColor("#1D2939")
MUTED=colors.HexColor("#667085"); PALE=colors.HexColor("#F3F6FA"); LINE=colors.HexColor("#D8E0EA")
BODY=ParagraphStyle("body",fontName="Arabic",fontSize=10.1,leading=16.3,alignment=TA_RIGHT,textColor=INK,wordWrap="RTL",spaceAfter=4)
SMALL=ParagraphStyle("small",parent=BODY,fontSize=8.2,leading=12.4,textColor=MUTED)
H1=ParagraphStyle("h1",fontName="ArabicBold",fontSize=18,leading=25,alignment=TA_RIGHT,textColor=NAVY,wordWrap="RTL",spaceBefore=9,spaceAfter=7)
H2=ParagraphStyle("h2",fontName="ArabicBold",fontSize=13.5,leading=20,alignment=TA_RIGHT,textColor=BLUE,wordWrap="RTL",spaceBefore=8,spaceAfter=5)
H3=ParagraphStyle("h3",fontName="ArabicBold",fontSize=11.3,leading=17,alignment=TA_RIGHT,textColor=NAVY,wordWrap="RTL",spaceBefore=5,spaceAfter=3)

def p(x,style=BODY): return Paragraph(rtl(x),style)
def h1(x): return p(x,H1)
def h2(x): return p(x,H2)
def h3(x): return p(x,H3)
def bullet(x,c=BLUE):
    t=Table([[p(x),Paragraph("●",ParagraphStyle("dot",fontName="Helvetica-Bold",fontSize=7,textColor=c,alignment=TA_CENTER))]],colWidths=[159*mm,6*mm])
    t.setStyle(TableStyle([("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),0),("RIGHTPADDING",(0,0),(-1,-1),0),("TOPPADDING",(0,0),(-1,-1),1),("BOTTOMPADDING",(0,0),(-1,-1),1)])); return t
def note(title,text,c=BLUE):
    t=Table([[p(title,H3)],[p(text)]],colWidths=[165*mm])
    t.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),colors.Color(c.red,c.green,c.blue,alpha=.10)),("BOX",(0,0),(-1,-1),1,c),("LINEBEFORE",(0,0),(0,-1),4,c),("LEFTPADDING",(0,0),(-1,-1),9),("RIGHTPADDING",(0,0),(-1,-1),9),("TOPPADDING",(0,0),(-1,-1),6),("BOTTOMPADDING",(0,0),(-1,-1),6)])); return t
def table(headers,rows,widths=None,severity=None):
    th=ParagraphStyle("th",parent=SMALL,fontName="ArabicBold",textColor=colors.white,alignment=TA_CENTER)
    data=[[p(x,th) for x in headers]]+[[p(x,SMALL) for x in r] for r in rows]
    widths=widths or [165*mm/len(headers)]*len(headers)
    t=Table(data,colWidths=widths,repeatRows=1,hAlign="RIGHT")
    cmd=[("BACKGROUND",(0,0),(-1,0),NAVY),("GRID",(0,0),(-1,-1),.45,LINE),("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),5),("RIGHTPADDING",(0,0),(-1,-1),5),("TOPPADDING",(0,0),(-1,-1),5),("BOTTOMPADDING",(0,0),(-1,-1),5)]
    for i in range(1,len(data)): cmd.append(("BACKGROUND",(0,i),(-1,i),colors.white if i%2 else PALE))
    if severity is not None:
        for i,r in enumerate(rows,1):
            s=str(r[severity]); c=RED if "حرج" in s else ORANGE if "عال" in s else BLUE if "متوسط" in s else GREEN
            cmd.append(("BACKGROUND",(severity,i),(severity,i),colors.Color(c.red,c.green,c.blue,alpha=.14)))
    t.setStyle(TableStyle(cmd)); return t

class Doc(BaseDocTemplate):
    def __init__(self,path):
        super().__init__(path,pagesize=A4,rightMargin=22*mm,leftMargin=22*mm,topMargin=22*mm,bottomMargin=20*mm,title="Kit, Caisson Tunnel, Glass and Tempered Glass audit",author="Codex")
        self.addPageTemplates(PageTemplate(id="p",frames=Frame(self.leftMargin,self.bottomMargin,self.width,self.height,id="f"),onPage=self.page))
    def page(self,c,d):
        c.saveState(); c.setFillColor(NAVY); c.rect(0,A4[1]-10*mm,A4[0],10*mm,fill=1,stroke=0)
        c.setFont("Arabic",8); c.setFillColor(colors.white); c.drawRightString(A4[0]-20*mm,A4[1]-6.5*mm,rtl("تدقيق الكِت وصندوق النفق والزجاج"))
        c.setStrokeColor(LINE); c.line(20*mm,14*mm,A4[0]-20*mm,14*mm); c.setFillColor(MUTED); c.drawRightString(A4[0]-20*mm,9*mm,rtl(f"الصفحة {d.page}")); c.drawString(20*mm,9*mm,"ERP Alum - Technical Audit"); c.restoreState()

s=[]
s += [Spacer(1,23*mm),p("التشخيص التقني الشامل",ParagraphStyle("cover",parent=H1,fontSize=27,leading=37,alignment=TA_CENTER)),p("الكِت - Caisson Tunnel - الزجاج - Verre Trempé",ParagraphStyle("cover2",parent=H1,fontSize=20,leading=30,alignment=TA_CENTER,textColor=BLUE)),Spacer(1,9*mm)]
s.append(Table([["KIT BUNDLES","CAISSON TUNNEL","GLASS","VERRE TREMPÉ"]],colWidths=[41*mm]*4,style=TableStyle([("BACKGROUND",(0,0),(-1,-1),NAVY),("TEXTCOLOR",(0,0),(-1,-1),colors.white),("FONTNAME",(0,0),(-1,-1),"Helvetica-Bold"),("FONTSIZE",(0,0),(-1,-1),8.5),("ALIGN",(0,0),(-1,-1),"CENTER"),("TOPPADDING",(0,0),(-1,-1),10),("BOTTOMPADDING",(0,0),(-1,-1),10),("GRID",(0,0),(-1,-1),.5,colors.white)])))
s += [Spacer(1,10*mm),note("الخلاصة الصريحة","النظام غني وظيفيًا، لكنه ليس منظومة تصنيع موحّدة بعد. الكِت وصندوق النفق والزجاج العادي والزجاج المقسّى تستخدم نماذج بيانات وحسابات ومسارات تسعير مختلفة، وبعضها يعتمد على قيم افتراضية صامتة. أخطر نقطة مؤكدة هي وجود أسعار ومقاسات تشغيلية ثابتة داخل شاشة الزجاج المقسّى، ما يسمح بإنتاج تكلفة صحيحة شكليًا لكنها منفصلة عن إدارة الأسعار.",RED),Spacer(1,6*mm),p("نطاق التدقيق: صفحات المنتجات والأسعار، قاعدة SQLite، محرك BOM، جدول الكميات، ورقة القص، إدراج الطلب، التعديل، PDF، والمزامنة. هذا تدقيق ساكن للكود مع محاولة تشغيل الاختبارات؛ تشغيل مجموعة Flutter المخصصة لم يكتمل ضمن مهلة الفحص ولم يُستخدم كدليل نجاح.",SMALL),PageBreak()]

s += [h1("1. الحكم التنفيذي"),table(["المجال","الحكم","الخطورة"],[
    ["الكِتات","النموذج يدعم عائلات ونطاقات وآليات وعددًا لكل ضلفة، لكن المنطق موزع بين الواجهة وقاعدة البيانات ومحرك BOM، والافتراضات الصامتة كثيرة.","عال"],
    ["Caisson Tunnel","آلة الحاسبة المستقلة واضحة، لكنّها تحسب مواد محدودة بمسطرة ثابتة 6000 مم وإضافتي 110/160 مم، بينما BOM داخل الطلب يملك مسارًا آخر أوسع؛ خطر اختلاف النتيجة قائم.","حرج"],
    ["الزجاج العادي","يدعم مفردًا ومزدوجًا ومورقًا ومقسّى وفواصل وغازًا وبانوهات، لكن الهوية والتجميع والسعر موزعة بين Glass ومواصفات الرسم.","عال"],
    ["الزجاج المقسّى","وظائف رسم وثقوب وكِتات وقواعد وPDF واسعة، لكن ملف الشاشة يتجاوز 12 ألف سطر ويحتوي أسعار fallback ثابتة، وهذا يمنع الاعتماد المالي الكامل.","حرج"],
    ["الاختبارات","توجد اختبارات نوعية ممتازة، لكن لا توجد بوابة موحدة مثبتة تغطي السيناريو الكامل من المنتج إلى المخزون والفاتورة.","عال"],
],[50*mm,91*mm,24*mm],2),Spacer(1,5*mm),h2("ما هو جيد فعلًا"),bullet("KitBundles يدعم عنصرًا ثابتًا، عنصرًا حسب مجال قياس، variants، عائلات داخل الكِت، توافق الآلية، توافق نوع اللام، وخيار per_leaf."),bullet("محرك BOM يحافظ على اسم الكِت الفرنسي، يربط catalogItemId، ويستطيع تفجير مركبات الكِت بدل احتساب الحاوية مرتين."),bullet("الزجاج المزدوج يفصل الوجه الخارجي والداخلي والفاصل والغاز والتقسية في التسعير والوصف."),bullet("Verre trempé يملك جداول مستقلة للأنظمة والكِتات والثقوب والمكونات والقواعد، وتوجد شاشة إدارة مخصصة."),bullet("توجد اختبارات موجهة للكِت، صندوق النفق، الزجاج، fit المفصل/الزجاج، وورقة المواد المطلوبة.")]

s += [h1("2. خريطة البيانات والتدفق"),table(["النطاق","المصدر","المستهلكون","الملاحظة"],[
    ["الكِت","KitBundles + العائلات + العناصر + النطاقات + variants","محرك BOM، ورقة القص، required goods، إدارة الأسعار","حاوية منطقية ومكونات فعلية؛ يجب منع جمع سعر الاثنين."],
    ["النفق","ShutterComponents من نوع caisson_tunnel + CaissonTunnelPrices + payload الطلب","الحاسبة، النتيجة، الفاتورة، PDF، BOM","يوجد تمثيلان للسعر: منتج شتر وسعر متر خطي مستقل."],
    ["الزجاج","Glass + GlassColorPrices + GlassSpecification داخل الرسم","BOM، التسعير، devis، القص، المخزون","المواصفة التشغيلية أغنى من صف المنتج، والربط يعتمد على id وخصائص وصفية."],
    ["المقسّى","TemperedGlassItems/Systems/Kits/Holes/Components/Rules + payload الرسم","شاشة العمل، PDF التصنيع، الطلب، التسعير","منظومة شبه مستقلة عن Glass العادي."],
],[37*mm,45*mm,43*mm,40*mm]),Spacer(1,5*mm),note("خطر الحدود بين النماذج","كل انتقال بين هذه الجداول وpayload الطلب يحتاج عقدًا واضحًا: إصدار schema، معرفات مستقرة، وحدة قياس، مصدر السعر، وسياسة fallback. حاليًا بعض الانتقالات تقبل القيم الناقصة وتستبدلها بصفر أو قيمة ثابتة من دون منع الحفظ.",ORANGE)]

s += [h1("3. تشخيص الكِتات Kit Bundles"),h2("المشكلات المؤكدة"),table(["المشكلة","الأثر","الخطورة"],[
    ["الواجهة 2243 سطرًا وتجمع CRUD والعائلات والنطاقات والـvariants والتوافق في ملف واحد.","صعوبة اختبار القواعد وإعادة استخدامها؛ تعديل صغير قد يكسر اختيار الكِت أو كميته.","عال"],
    ["عدة catch فارغة عند تحميل العائلات/القواعد/الـvariants.","الفشل يتحول إلى قائمة فارغة وكأن الكِت بلا عناصر؛ لا يعرف المستخدم أن البيانات لم تُحمّل.","حرج"],
    ["الكمية والوحدة عند إضافة مكوّن تضبط افتراضيًا كقطعة، بينما بعض المكونات قد تكون مترًا أو زوجًا أو طقمًا.","مخزون وتكلفة غير صحيحين عند تفجير الكِت.","عال"],
    ["مطابقة الكِت تعتمد جزئيًا على الاسم والتوكنات والوصف إلى جانب المعرف.","إعادة تسمية أو اختلاف لغة/هجاء قد يختار كِتًا خاطئًا أو لا يختار شيئًا.","عال"],
    ["النطاق يستخدم حدين شاملين min وmax؛ حدود متجاورة قد تتطابق مع صفين، ويُختار الأول بعد الفرز في بعض الأبعاد.","قرار غير صريح عند القيمة الحدية، خصوصًا الوزن.","متوسط"],
    ["سعر حاوية KitBundle وسعر الأطفال موجودان في أكثر من مصدر.","احتمال double counting أو صفر تكلفة بحسب showKitRow/grouping والمسار المستهلك.","حرج"],
],[78*mm,63*mm,24*mm],2),h2("النواقص الوظيفية"),bullet("لا توجد معاينة محاكاة داخل صفحة الكِت تعرض: مدخلات العرض/الارتفاع/الوزن/الآلية ثم العناصر المختارة والسبب والكمية والتكلفة."),bullet("لا يوجد validator يمنع تداخل النطاقات أو وجود فجوات بينها أو family بلا أطفال أو component محذوف."),bullet("لا يوجد إصدار Version للكِت يحفظ snapshot عند الطلب؛ تعديل الكِت لاحقًا قد يغير إعادة حساب طلب قديم."),bullet("لا توجد وحدة صريحة kit/pcs/pair/m/ml/kg لكل طفل مع تحويل موحد للمخزون."),bullet("لا يظهر أثر per_leaf بوضوح في شاشة النتائج: المطلوب عرض عدد الكِت، ثم عناصره الفعلية وكميتها، لا عبارة عامة مثل 6 éléments."),h2("الإصلاح المقترح"),bullet("إنشاء KitResolver نقي يستقبل KitContext ويرجع KitResolution مع أسباب الاختيار والتحذيرات."),bullet("تخزين kit_snapshot_json وkit_version وresolved_at في بند الطلب."),bullet("منع الحفظ إذا كانت النطاقات متداخلة أو ناقصة، وإذا كان السعر صفراً دون تصريح admin."),bullet("اعتماد UUID ومعرف role ثابت بدل الاسم بوصفه مفتاح منطق.")]

s += [PageBreak(),h1("4. تشخيص Caisson Tunnel"),h2("ما تفعله الحاسبة الحالية"),bullet("تخزن الطول الداخلي بالمليمتر والكمية وحجم 25/30/40 سم."),bullet("تضيف 110 مم لكِت 11 أو 160 مم لكِت 16 إلى طول قطع الصندوق، بينما الغطاء السفلي يبقى بالطول الأصلي."),bullet("تحسب عدد بارات 6000 مم بقسمة القطع الممكنة في البارة ثم التقريب للأعلى."),bullet("تحفظ payload مستقلًا في الطلب وتعرض شاشة نتيجة وجدولًا قابلًا للتعديل."),h2("المخاطر والأخطاء"),table(["المشكلة","لماذا هي خطرة","الخطورة"],[
    ["طول البارة 6000 مم ثابت في الكود، رغم أن قاعدة منتجات الشتر تحتوي bar_length_m.","أي مورد أو منتج بطول 5.8 أو 6.5 م يعطي شراء وهدرًا خاطئين.","حرج"],
    ["إضافتا 110/160 مم ثابتتان ومربوطتان باسم kit11/kit16.","لا يمكن إدارة سماحات جديدة من المنتجات أو حسب المقاس/اللون/المورد.","عال"],
    ["الحاسبة المستقلة تحسب الصندوق والغطاء السفلي والأزواج، ومحرك BOM يحسب كِت النفق والمحرك واللام والمحور عبر مسار آخر.","يمكن أن تختلف شاشة النتيجة عن required goods وfiche de coupe والفاتورة.","حرج"],
    ["سعر Caisson Tunnel يظهر كـShutterComponent وكجدول CaissonTunnelPrices.","مصدر الحقيقة غير وحيد؛ تعديل سعر قد لا يصل لكل المستهلكين.","حرج"],
    ["المدخل يقبل كمية غير صالحة ثم يستبدلها 1 بدل إيقاف الحفظ.","خطأ إدخال يتحول بصمت إلى أمر تصنيع حقيقي.","عال"],
    ["لا تدخل kerf، سماحة تشذيب، اتجاه لون، بقايا مخزون، أو استراتيجية تجميع قطع متعددة.","عدد البارات نظري وليس optimizer تصنيع كامل.","عال"],
],[74*mm,67*mm,24*mm],2),h2("حالات يجب اختبارها"),bullet("قطعة 5890 مم مع kit16: تصبح 6050 مم وتتطلب بارتين أو سياسة رفض؛ يجب أن يظهر السبب."),bullet("عدة قطع قصيرة بأحجام 25/30/40: يجب عدم دمج خامات مختلفة، مع استغلال البقايا داخل الحجم نفسه."),bullet("تقسيم الستار إلى جزأين: كِت ومحرك/مانيفال ومحور وسكك ولامات لكل جزء، وإعادة اختيار اللام حسب عرض كل جزء."),bullet("كمية طلب أكبر من 1 مع splits: منع الضرب مرتين بين createShutter وsplitCount."),bullet("منتج نفق غير مسعّر أو غير نشط: منع اعتماد تكلفة صفر وإظهار تنبيه قابل للتتبع.")]

s += [PageBreak(),h1("5. تشخيص الزجاج العادي والبانوهات"),h2("التغطية الحالية"),bullet("زجاج مفرد ومزدوج، طبقتان مستقلتان، سماكات وألوان وتشطيبات، laminated، tempered، فاصل، غاز، وبانوهات مغلقة/ديكور."),bullet("BOM يحسب المساحة من أبعاد القطعة ويجمع القطع المتطابقة، ويخزن catalogItemId عند توفره."),bullet("صفحة المنتجات مستقلة للزجاج، وإدارة الأسعار تدعم Glass وGlassColorPrices."),h2("الثغرات"),table(["المشكلة","النتيجة","الخطورة"],[
    ["القيمة غير القابلة للتحويل في صفحة المنتج تصبح 0.0.","زجاج أو سماكة أو سعر صفر يمكن حفظه إذا لم يلتقطه validator اللاحق.","عال"],
    ["البانوهات تسجل price_per_sqm بصفر في بعض مسارات CRUD وتعتمد حقولًا أخرى.","مستهلك يقرأ الحقل العام قد يعرض صفراً رغم وجود سعر القطعة/اللوح.","عال"],
    ["هوية التجميع تصنع من catalog id والوصف النصي بعد إزالة label.","تغير صياغة الوصف يمنع الدمج؛ وصف متشابه قد يدمج قطعتين تختلفان بخاصية غير ظاهرة.","عال"],
    ["لا يظهر في كل مسار تحقق صريح من أبعاد اللوح الخام وحدود الدوران واتجاه النقشة.","الكمية النظرية بالمتر المربع قد تكون غير قابلة للقص من الألواح المتاحة.","حرج"],
    ["الزجاج المشكل يسعّر كمستطيل محيط في بعض الحالات.","التكلفة لا تفصل هدر الشكل وCNC والحواف وعدد الرؤوس.","عال"],
    ["الحذف يستخدم tombstone للزجاج في مزامنة عامة، لكن العلاقات التاريخية يجب أن تعتمد snapshot.","منتج محذوف قد يجعل طلبًا قديمًا غير قابل لإعادة العرض أو إعادة الحساب بدقة.","عال"],
],[74*mm,67*mm,24*mm],2),h2("ما ينقص إدارة المنتج"),bullet("أبعاد اللوح الخام: العرض، الارتفاع، السماكة، قابلية الدوران، اتجاه النقشة، الحد الأدنى للبقايا، والمورد."),bullet("سعر شراء وسعر بيع وتاريخ صلاحية السعر، لا حقل سعر واحد فقط."),bullet("خدمات منفصلة: قص مستقيم، CNC، ثقب، شطف، تلميع، تقسية، ترقيق، غاز، وفاصل."),bullet("معرف SKU/UUID ثابت لكل توليفة بدل الاعتماد على الاسم واللون النصي."),bullet("قواعد توافق سماكة الزجاج مع parclose/joint يجب أن تمنع الحفظ لا أن تكتفي بتحذير بصري.")]

s += [PageBreak(),h1("6. تشخيص Verre Trempé"),note("أكبر خلل مالي","شاشة العمل تحتوي أسعار fallback ثابتة للزجاج والحواف والسفع، وللمقابض والسكة والمفصل والـpivot والجوانات. إذا فشل تحميل قاعدة البيانات أو لم توجد مادة، تستمر الحسبة بأرقام داخل الكود. هذا يجعل إدارة الأسعار غير مرجع وحيد ويخفي نقص الكتالوج.",RED),h2("أدلة من المسار الحالي"),bullet("معدل زجاج أساسي يقارب 3500 دج/م² مع إضافات ثابتة بحسب السماكة."),bullet("معدل الحافة 350 أو 600 دج/م، والسفع 1200 دج/م²."),bullet("fallbacks للإكسسوارات مثل المقبض والسكة والمفصل والـpivot والجوانات عند غياب العنصر."),bullet("عدة عمليات تحميل محاطة بـcatch فارغ؛ الفشل قد يقود مباشرة إلى بيانات fallback."),bullet("ملف الشاشة 12171 سطرًا يجمع النموذج، القواعد، الرسم، التفاعل، التسعير، الجدول، serialization والمعاينة."),h2("المشكلات الهندسية والتشغيلية"),table(["المشكلة","الأثر","الخطورة"],[
    ["قواعد هندسية ثابتة: زيادات 30 مم، أبعاد افتراضية، مسافات ثقوب ومقابض.","لا يمكن تخصيصها حسب النظام أو المورد أو الكِت دون تعديل الكود.","حرج"],
    ["clamp للإحداثيات داخل حدود اللوح بدل رفض موضع غير صالح.","الثقب الخاطئ قد يتحرك بصمت إلى الحافة ويبدو صالحًا في الرسم.","حرج"],
    ["قواعد الثقوب والكِتات موجودة في DB، لكن توجد defaults موازية في الشاشة والنماذج.","مصدران للحقيقة ونتائج مختلفة بعد فشل التحميل.","حرج"],
    ["لا تظهر بوضوح قواعد الحد الأدنى للمسافة بين الثقوب/الحواف/الزوايا لكل مصنع.","احتمال كسر اللوح بعد التقسية أو رفضه عند المورد.","حرج"],
    ["الحساب يجمع المساحة والمحيط، لكنه لا يثبت دائمًا source id لكل خدمة.","يصعب تتبع سبب السعر أو مراجعته بعد التعديل.","عال"],
    ["PDF التصنيع يقبل قيم fallback عند غياب السمك/القطر/الإحداثيات.","ملف مصنع مكتمل شكليًا ببيانات افتراضية غير مؤكدة.","حرج"],
],[74*mm,67*mm,24*mm],2)]

s += [PageBreak(),h1("7. المزامنة والتسعير والمخزون"),table(["المجال","الوضع","الفجوة"],[
    ["Price Sync","يشمل CaissonTunnelPrices وGlass وGlassColorPrices وTemperedGlassItems.","لا يكفي إن بقيت أسعار fallback داخل الواجهة؛ كما يجب مزامنة قواعد الخدمات والكِتات وإصداراتها."],
    ["Catalog Sync","الزجاج العام لديه مسارات مزامنة وحذف منطقي.","يجب إثبات شمول كل جداول TemperedGlassSystems/Kits/Holes/Components/Rules وKitBundleFamilies/Ranges/Variants بعقد واحد."],
    ["المخزون","BOM يستخدم inventoryItemType وcatalogItemId في مسارات عديدة.","الخدمات غير المخزنية يجب فصلها عن المادة، والوحدات يجب توحيدها قبل الخصم."],
    ["الطلب التاريخي","payload يحتفظ بالرسم والمواصفات.","يلزم snapshot كامل للأسعار والقواعد والكِت والمادة؛ إعادة الحساب بكتالوج اليوم ليست تدقيقًا تاريخيًا."],
],[37*mm,58*mm,70*mm]),h2("قواعد إلزامية"),bullet("لا يسمح بحفظ أو إرسال تصنيع إذا كان أي بند مادي بسعر شراء مجهول أو معرف منتج مفقود، إلا بصلاحية override مع سبب."),bullet("كل صف تكلفة يحمل price_source_id وprice_version وcalculation_rule_version."),bullet("المخزون يخصم بوحدة أساسية واحدة لكل SKU، والتحويل من kit/pair/bar/m² موثق وقابل للاختبار."),bullet("أي فشل مزامنة يعرض حالة stale ووقت آخر مزامنة؛ لا يتحول إلى صفر أو fallback صامت."),bullet("حذف المنتج لا يمس snapshots الطلبات السابقة.")]

s += [PageBreak(),h1("8. تجربة المستخدم والرقابة"),h2("نواقص الواجهة"),bullet("لا توجد شاشة واحدة لتفسير لماذا اختير هذا الكِت أو هذه اللام أو هذه القاعدة."),bullet("لا توجد مقارنة قبل/بعد عند تغيير التقسيم أو الآلية أو السمك تبين فروق المواد والتكلفة."),bullet("الخطأ الصامت في التحميل غير مميز عن قائمة فارغة حقيقية."),bullet("القيم الافتراضية لا تحمل شارة افتراضي/غير مؤكد في النتيجة أو PDF."),bullet("تعدد اللغات جيد بصريًا، لكن الأسماء المترجمة ما زالت تدخل في بعض عمليات المطابقة."),h2("لوحة جودة مطلوبة"),table(["المؤشر","الحد المقبول"],[
    ["بنود بلا catalogItemId","صفر قبل اعتماد الطلب"],
    ["أسعار صفر غير مصرح بها","صفر"],
    ["fallbacks مستخدمة في حساب إنتاج","صفر"],
    ["نطاقات كِت متداخلة أو بها فجوات","صفر"],
    ["ثقوب تخالف edge distance","صفر"],
    ["فرق تكلفة بين شاشة النتيجة وBOM","أقل من 0.01 دج"],
    ["فرق الكمية بين BOM وfiche de coupe والمخزون","صفر"],
],[105*mm,60*mm]),h2("السجل المطلوب"),bullet("Calculation trace لكل بند: المدخلات، القاعدة، النسخة، الناتج، التقريب، والمصدر."),bullet("Audit log لتعديل الكِت والقواعد والأسعار، مع المستخدم والوقت والقيمة القديمة والجديدة."),bullet("معرف correlation واحد يربط الطلب بـBOM وورقة القص والحجز المخزني وPDF.")]

s += [PageBreak(),h1("9. خطة الاختبار المطلوبة"),table(["المستوى","الاختبارات"],[
    ["Unit","حدود كل range، per_leaf، families، weight groups، bar packing، وحدات القياس، سعر طبقات الزجاج، الخدمات، edge distances."],
    ["Property-based","أي تقسيم يحافظ على مجموع العرض؛ لا كمية سالبة؛ لا ثقب خارج اللوح؛ لا تكلفة NaN؛ زيادة الكمية تضاعف الناتج مرة واحدة فقط."],
    ["Golden","رسومات/PDF لكل نظام زجاج مقسّى ولكل اتجاه مفصل ومقبض وثقب، وثيم فاتح/داكن."],
    ["Integration","منتج -> سعر -> رسم -> BOM -> required goods -> fiche de coupe -> حجز مخزون -> فاتورة -> إعادة فتح الطلب."],
    ["Migration","فتح payload قديم قبل إضافة الحقول، وحذف/إعادة تسمية منتج مرتبط بطلب قديم."],
    ["Offline/Sync","تعديل kit/rule/price على جهازين، وحل التعارض دون فقد أطفال الكِت أو الثقوب."],
],[35*mm,130*mm]),h2("سيناريوهات قبول حاسمة"),bullet("ستار 2400 مم مقسوم إلى جزأين: إعادة اختيار اللام المناسبة لكل 1200 مم، كِت لكل جزء، ومحرك/مانيفال حسب الاختيار، بلا مضاعفة ثانية بسبب quantity."),bullet("Caisson بطول يتجاوز البارة بعد سماحة kit: رفض أو تفصيل متعدد موضح، لا تقريب صامت."),bullet("زجاج مزدوج: وجهان بأسعار وسماكات مختلفتين + فاصل + غاز + تقسية طبقة واحدة؛ مجموع التفاصيل يساوي الإجمالي."),bullet("Verre trempé بمنتج مفقود: يمنع الاعتماد ويحدد المنتج الناقص، ولا يستعمل 3800/4500/16500 ثابتة."),bullet("نفس الطلب بعد تغيير الأسعار: العرض التاريخي ثابت؛ إعادة التسعير عملية صريحة تنتج نسخة جديدة.")]

s += [PageBreak(),h1("10. خارطة الإصلاح بالأولوية"),table(["الأولوية","الإجراء","معيار الإغلاق"],[
    ["P0","إزالة كل أسعار fallback من Verre trempé، وتحويلها إلى خطأ بيانات مانع.","لا رقم مالي في كود الواجهة؛ كل سعر له سجل ومصدر."],
    ["P0","توحيد محرك Caisson Tunnel بين الحاسبة وBOM وPDF وrequired goods.","نفس المدخل يعطي نفس القطع والكميات والتكلفة في كل الشاشات."],
    ["P0","اعتماد source of truth واحد لسعر النفق ومنع السعر الصفري غير المصرح.","اختبار تكاملي يثبت تحديث السعر في كل المخرجات."],
    ["P0","Validator صناعي للثقوب والحواف والزوايا قبل PDF.","لا يمكن تصدير لوحة مخالفة."],
    ["P1","استخراج KitResolver وTemperedGlassCalculator وGlassGeometryValidator كخدمات نقية.","ملفات صغيرة واختبارات وحدة بلا Widget."],
    ["P1","Snapshot/version للكِت والقواعد والأسعار داخل الطلب.","إعادة فتح طلب قديم تعطي نفس الناتج."],
    ["P1","تعريف وحدات موحد وتحويلات للمخزون.","لا خصم kit على أنه piece ولا bar على أنه meter دون conversion."],
    ["P2","محسن قص ألواح للزجاج وبقايا مع اتجاه نقش وkerf.","خطة ألواح قابلة للطباعة والحجز."],
    ["P2","Calculation trace ولوحة جودة وأخطاء قابلة للتشخيص.","كل بند يشرح كيف ولماذا حُسب."],
],[20*mm,105*mm,40*mm]),Spacer(1,5*mm),note("الترتيب الصحيح","لا تبدأ بتحسين شكل الجداول قبل إزالة مصادر الأسعار الموازية وتوحيد المحركات. الأولوية لصحة الكمية والسعر وقابلية التتبع، ثم تحسين الواجهة.",ORANGE)]

s += [PageBreak(),h1("11. ملفات محورية راجعها التدقيق"),table(["الملف/الوحدة","الدور"],[
    ["kit_bundles_screen.dart","إدارة الكِت والعائلات والنطاقات والـvariants."],
    ["calculate_component.dart","اختيار الكِت وتفجيره وحساب الزجاج وBOM."],
    ["caisson_tunnel_screen.dart / result","حاسبة النفق وpayload والنتيجة."],
    ["glass.dart / price_management_screen.dart","منتجات وأسعار الزجاج والبانوهات."],
    ["tempered_glass_items_screen.dart","كتالوج إكسسوارات وقطاعات الزجاج المقسّى."],
    ["glass_systems_rules_screen.dart","الأنظمة والكِتات والثقوب والقواعد."],
    ["tempered_glass_work_screen.dart","الرسم والهندسة والحساب والتسعير والإدراج."],
    ["glass_fabrication_pdf_service.dart","ملف تصنيع الزجاج المقسّى."],
    ["sql_database.dart","جداول CRUD والبذور والعلاقات."],
    ["price_sync_service.dart","نطاق مزامنة الأسعار."],
    ["order_required_goods_screen.dart / pdf_fiche_coupe_api.dart","تحويل BOM إلى احتياج وقص."],
],[75*mm,90*mm]),Spacer(1,6*mm),h2("الخلاصة النهائية"),note("التقييم بلا مجاملة","المنتج متقدم من حيث عدد الميزات، لكنه يحمل دينًا تقنيًا خطيرًا في قلب التصنيع: قواعد وأسعار افتراضية داخل واجهات ضخمة، أكثر من مسار حساب لنفس المادة، ومزج بين الاسم والمعرف. قبل الاعتماد التجاري الكامل، يجب إنجاز P0 وإثبات التطابق بين الطلب وBOM والقص والمخزون والفاتورة باختبارات تكامل قابلة لإعادة التشغيل.",RED),Spacer(1,8*mm),p("تاريخ التدقيق: 17 أكتوبر 2026. التشخيص مبني على نسخة مساحة العمل الحالية ولا يدّعي صحة بيانات الموردين أو الأسعار الفعلية خارج المستودع.",SMALL)]

Doc(str(OUT)).build(s)
print(OUT)
