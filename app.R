# app.R — Brain Health QI QC report generator (in-window report viewer)
#
# Workflow: upload HCO Excel template -> data-handling.Rmd builds df/df.wide.tot
# -> analysis.Rmd renders the HTML report, which is displayed in the app window.
# A download button is also available to save the displayed report.
#
# Both Rmds are rendered in ONE shared environment, mimicking your interactive
# workflow (needed so e.g. `all.dat2.` carries over to analysis.Rmd for type=2).
#
# Files needed in the app folder: app.R, data-handling.Rmd, analysis.Rmd
#
# Packages: shiny, rmarkdown, readxl, plus everything the Rmds use
# (here, gt, gtsummary, tidyverse, kableExtra, flextable, legendry, patchwork)

library(shiny)
library(readxl)

# No HCO prompt: reports carry no organization label. Internally the scripts
# analysis.Rmd neutralizes all displayed org labels (facets, tables, titles).

# Folder where finished reports live, served to the browser as /reports/...
reports_dir <- file.path(tempdir(), "shiny-reports")
dir.create(reports_dir, showWarnings = FALSE)
shiny::addResourcePath("reports", reports_dir)

ui <- fluidPage(
  titlePanel("Brain Health QI — QC Data Report"),
  sidebarLayout(
    sidebarPanel(
      fileInput(
        "xlsx", "Upload HCO data template",
        accept = c(".xlsx", ".xls", ".xlsm")  # .xlsm (org B) handled automatically
      ),
      radioButtons(
        "type", "Data entry template type",
        choices = c("Option 1 — quarterly" = 1,
                    "Option 2 — monthly"   = 2),
        selected = 1
      ),
      actionButton("generate", "Generate report", class = "btn-primary"),
      conditionalPanel(
        condition = "output.report_ready",
        br(),
        radioButtons(
          "dl_format", "Download format",
          choices = c("Word (.docx)" = "word", "HTML" = "html"),
          selected = "word", inline = TRUE
        ),
        downloadButton("download", "Download report")
      ),
      width = 3
    ),
    mainPanel(
      tabsetPanel(
        id = "tabs",
        tabPanel(
          "Check upload",
          br(),
          uiOutput("merge_warning"),
          h4("Sheets found in uploaded file"),
          helpText("Use this to confirm the right template was uploaded before generating the report."),
          verbatimTextOutput("sheets")
        ),
        tabPanel(
          "Report",
          br(),
          uiOutput("report_view")
        )
      ),
      width = 9
    )
  )
)

server <- function(input, output, session) {

  # Filename (within reports_dir) of the most recently rendered report
  report_file <- reactiveVal(NULL)

  # Context of the last successful render (workdir + shared environment +
  # params), so the Word download can re-render analysis.Rmd without
  # re-processing the data
  render_ctx <- reactiveVal(NULL)

  # Lets the UI know a report exists (controls the download button)
  output$report_ready <- reactive({ !is.null(report_file()) })
  outputOptions(output, "report_ready", suspendWhenHidden = FALSE)

  # Reminder from data-handling.Rmd about the language-tab merged cells
  output$merge_warning <- renderUI({
    if (input$type == 1) {
      div(
        style = "background:#fff3cd; border:1px solid #ffeeba; padding:10px; border-radius:4px; margin-bottom:15px;",
        strong("Reminder (option 1 templates): "),
        "in the 'Data Entry race, ethn, & lang' sheet, Column A, rows 8-31 of the ",
        "Measure 1 language section must be merged before upload, or totals ",
        "will be incorrect."
      )
    }
  })

  # Path to the uploaded file, copied with a clean .xlsx extension.
  # This also covers org B .xlsm files (readxl reads them fine; no
  # manual copy/rename needed anymore).
  xlsx_path <- reactive({
    req(input$xlsx)
    clean <- file.path(tempdir(), "uploaded-data.xlsx")
    file.copy(input$xlsx$datapath, clean, overwrite = TRUE)
    clean
  })

  # Show sheet names so the user can verify the template
  output$sheets <- renderPrint({
    req(xlsx_path())
    cat(excel_sheets(xlsx_path()), sep = "\n")
  })

  # ---- Generate the report and show it in the Report tab ----
  observeEvent(input$generate, {
    req(xlsx_path())

    # Fresh working dir per render so no stale dat.RData carries over
    workdir <- file.path(tempdir(), paste0("render-", as.integer(Sys.time())))
    dir.create(workdir)
    file.copy("data-handling.Rmd", file.path(workdir, "data-handling.Rmd"))
    file.copy("analysis.Rmd",      file.path(workdir, "analysis.Rmd"))
    # Word reference template used by analysis.Rmd's word_document format,
    # if it has been added to the app folder
    if (file.exists("template2.docx"))
      file.copy("template2.docx", file.path(workdir, "template2.docx"))

    # Unique filename per run so the iframe never shows a cached old report;
    # no org name in the filename (reports are anonymous)
    out_name <- paste0("brain-health-QC-report-",
                       format(Sys.time(), "%Y%m%d-%H%M%S"), ".html")

    # Shared environment across both Rmds (replicates running them
    # back-to-back in one R session)
    shared_env <- new.env(parent = globalenv())
    type_num   <- as.numeric(input$type)

    # Internal org name required by the scripts' logic, derived from the
    # template type (see note at top of file); never shown in the report
    hco_real <- if (type_num == 2) "B" else "A"

    withProgress(message = "Generating report", value = 0, {

      incProgress(0.1, detail = "Step 1/2: reading and processing data...")
      tryCatch({
        rmarkdown::render(
          file.path(workdir, "data-handling.Rmd"),
          params = list(xlsx_path = xlsx_path(), type = type_num,
                        hco_name = hco_real),
          envir  = shared_env,
          quiet  = TRUE
        )

        incProgress(0.5, detail = "Step 2/2: building report...")

        # Forced to HTML; the Rmd's YAML lists word_document first.
        # self_contained html (the default) means the single file includes
        # all figures, so the iframe can display it directly.
        rmarkdown::render(
          file.path(workdir, "analysis.Rmd"),
          output_format = "html_document",
          output_file   = file.path(reports_dir, out_name),
          params        = list(type = type_num, hco_name = hco_real),
          envir         = shared_env,
          quiet         = TRUE
        )

        report_file(out_name)
        render_ctx(list(workdir = workdir, env = shared_env,
                        type = type_num, hco = hco_real))
        updateTabsetPanel(session, "tabs", selected = "Report")

      }, error = function(e) {
        # Print the complete error (including knitr's 'Quitting from lines
        # X-Y [chunk]' context) to the R console for diagnosis
        message("---- report render failed ----")
        message(paste(capture.output(print(e)), collapse = "\n"))
        showNotification(paste("Report failed:", conditionMessage(e),
                               "— see the R console for the failing chunk."),
                         type = "error", duration = NULL)
      })
    })
  })

  # Display the rendered report in an iframe
  output$report_view <- renderUI({
    if (is.null(report_file())) {
      helpText("Upload a file and click 'Generate report' to see it here.")
    } else {
      tags$iframe(
        src   = paste0("reports/", report_file()),
        style = "width:100%; height:85vh; border:1px solid #ddd; border-radius:4px;"
      )
    }
  })

  # Download the report currently on screen, in the chosen format.
  # HTML: the displayed file is copied directly (no re-render).
  # Word: analysis.Rmd is re-rendered to .docx in the stored environment —
  # the data are already processed, so only the figures/tables step re-runs.
  # If template2.docx is in the app folder it styles the Word output;
  # otherwise default Word styling is used.
  output$download <- downloadHandler(
    filename = function() {
      if (input$dl_format == "html") {
        report_file()
      } else {
        sub("\\.html$", ".docx", report_file())
      }
    },
    content = function(file) {
      ctx <- render_ctx()
      req(ctx)

      if (input$dl_format == "html") {
        file.copy(file.path(reports_dir, report_file()), file, overwrite = TRUE)
        return(invisible())
      }

      id <- showNotification("Rendering Word version...", duration = NULL,
                             closeButton = FALSE, type = "message")
      on.exit(removeNotification(id), add = TRUE)

      word_fmt <- if (file.exists(file.path(ctx$workdir, "template2.docx"))) {
        "word_document"                # uses the YAML opts incl. reference_docx
      } else {
        rmarkdown::word_document()     # override YAML so a missing template
      }                                # doesn't break the render

      rmarkdown::render(
        file.path(ctx$workdir, "analysis.Rmd"),
        output_format = word_fmt,
        output_file   = file,
        params        = list(type = ctx$type, hco_name = ctx$hco),
        envir         = ctx$env,
        quiet         = TRUE
      )
    }
  )
}

shinyApp(ui, server)
