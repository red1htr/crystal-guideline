
.class public Lcom/crystal/GuidelineService;
.super Landroid/app/Service;

.field private handler:Landroid/os/Handler;
.field private view:Lcom/crystal/GuidelineView;
.field private wm:Landroid/view/WindowManager;

# Default constructor — required by Android
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Landroid/app/Service;-><init>()V

    return-void
.end method

.method public onCreate()V
    .locals 4

    invoke-super {p0}, Landroid/app/Service;->onCreate()V

    new-instance v0, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
    move-result-object v1

    invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    iput-object v0, p0, Lcom/crystal/GuidelineService;->handler:Landroid/os/Handler;

    const-string v1, "window"

    invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
    move-result-object v1

    iput-object v1, p0, Lcom/crystal/GuidelineService;->wm:Landroid/view/WindowManager;

    return-void
.end method

.method public onStartCommand(Landroid/content/Intent;II)I
    .locals 4

    iget-object v0, p0, Lcom/crystal/GuidelineService;->handler:Landroid/os/Handler;

    if-eqz v0, :handler_missing

    new-instance v1, Lcom/crystal/ShowGuidelineRunnable;

    invoke-direct {v1, p0}, Lcom/crystal/ShowGuidelineRunnable;-><init>(Lcom/crystal/GuidelineService;)V

    const-wide/16 v2, 0x1388

    invoke-virtual {v0, v1, v2, v3}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

    :handler_missing
    const/4 v0, 0x1

    return v0
.end method

.method public createOverlay()V
    .locals 8

    new-instance v0, Lcom/crystal/GuidelineView;

    invoke-direct {v0, p0}, Lcom/crystal/GuidelineView;-><init>(Landroid/content/Context;)V

    iput-object v0, p0, Lcom/crystal/GuidelineService;->view:Lcom/crystal/GuidelineView;

    const/4 v1, 0x2
    const/4 v2, 0x0

    invoke-virtual {v0, v1, v2}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V

    new-instance v1, Landroid/view/WindowManager$LayoutParams;

    const/16 v2, 0x7F6
    const/4 v3, -0x1
    const/4 v4, -0x1
    const/16 v5, 0x228
    const/4 v6, -0x3

    invoke-direct/range {v1 .. v6}, Landroid/view/WindowManager$LayoutParams;-><init>(IIIII)V

    iget-object v2, p0, Lcom/crystal/GuidelineService;->wm:Landroid/view/WindowManager;

    if-eqz v2, :overlay_done

    invoke-interface {v2, v0, v1}, Landroid/view/WindowManager;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V

    :overlay_done
    return-void
.end method

.method public onBind(Landroid/content/Intent;)Landroid/os/IBinder;
    .locals 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public onDestroy()V
    .locals 2

    iget-object v0, p0, Lcom/crystal/GuidelineService;->wm:Landroid/view/WindowManager;

    iget-object v1, p0, Lcom/crystal/GuidelineService;->view:Lcom/crystal/GuidelineView;

    if-eqz v0, :remove_callbacks

    if-eqz v1, :remove_callbacks

    invoke-interface {v0, v1}, Landroid/view/WindowManager;->removeView(Landroid/view/View;)V

    :remove_callbacks
    iget-object v0, p0, Lcom/crystal/GuidelineService;->handler:Landroid/os/Handler;

    if-eqz v0, :destroy_service

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/os/Handler;->removeCallbacksAndMessages(Ljava/lang/Object;)V

    :destroy_service
    invoke-super {p0}, Landroid/app/Service;->onDestroy()V

    return-void
.end method
