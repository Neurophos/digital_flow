;; ============================================================================
;; RMgenRnm.il
;;
;; Bindkey: in a SCHEMATIC window, select one instance (or just have the
;; schematic open) and press the key. For that cell it:
;;   1. reads the port list (names + directions) live from the OA symbol
;;      terminals  -- the same information the `functional/verilog.v` shell holds;
;;   2. scaffolds a SystemVerilog real-number model (Cadence EE_pkg::EEnet)
;;      and writes it as  <cell>/functional/verilog.sv ;
;;   3. repoints  <cell>/functional/master.tag  from verilog.v -> verilog.sv
;;      (backing up the previous tag to master.tag.bak).
;;
;; This mirrors the hand flow used on pixel_hh: the functional view's master is
;; switched from the netlister's verilog.v shell to an EEnet RNM verilog.sv.
;; The generated body is a STUB (Z-state / 0 drivers, SPEC-TODO) -- fill in the
;; behavior; the port interface is complete and ready to compile.
;;
;; Load from .cdsinit_user:
;;   load("/projects/msic/msic_a0/users/robson/wksp1/cds/bindkeys/RMgenRnm.il")
;; Then press F8 in a schematic.
;; ============================================================================

RMrnmSvFile   = "verilog.sv"        ;; SV file name inside the functional view
RMrnmViewName = "functional"        ;; view that carries the model
RMrnmDryRun   = nil                 ;; t -> print to CIW, write nothing (default key override below)

;; Heuristic: port names matching any of these regexps are treated as DIGITAL
;; (plain logic) rather than analog EEnet. Tune for your naming. (pixel_hh:
;; ph_smp*, diag_en* are digital; everything else is electrical.)
RMrnmDigitalPats = '("^ph_" "_en$" "_en_b$" "^clk" "^rst" "_b$")

;; Port names matching any of these regexps are forced to `inout` regardless of
;; their OA terminal direction -- for shared multi-driver nets (buses, columns,
;; supplies) that resolve across several drivers. (pixel_hh: diag_bus, column.)
RMrnmForceInout = '("^diag_bus$" "^column$")

;; --- Python GUI editor (F8) -------------------------------------------------
;; The system python3 (3.6) lacks tkinter and breaks under Virtuoso's
;; LD_LIBRARY_PATH (it points at Xcelium libs); python3.12 has tkinter. So we
;; call 3.12 explicitly and scrub the polluting vars (keeping DISPLAY for X11).
RMrnmPython    = "/usr/bin/python3.12"
RMrnmEnvScrub  = "/usr/bin/env -u LD_LIBRARY_PATH -u PYTHONHOME -u PYTHONPATH"
RMrnmPyScript  = "/projects/msic/msic_a0/users/robson/wksp1/cds/bindkeys/rnm_editor.py"
RMrnmLastTarget = nil               ;; list(lib cell view) refreshed on editor exit

;; ---------------------------------------------------------------------------
;; Resolve the symbol cellview to read terminals from.
;;   one instance selected -> its master ; else the open schematic's symbol.
;; ---------------------------------------------------------------------------
(defun RMrnmSourceCV (win)
  (let (sel cv)
    (setq sel (and win (geGetSelSet win)))
    (cond
      ((and sel (equal (length sel) 1) (equal (car sel)~>objType "inst"))
        (car sel)~>master)
      ((setq cv (geGetEditCellView win))
        (or (and (ddGetObj cv~>libName cv~>cellName "symbol")
                 (dbOpenCellViewByType cv~>libName cv~>cellName "symbol" "" "r"))
            cv))
      (t nil))))

(defun RMrnmIsDigital (nm)
  ;; coerce to strict t/nil so (equal flag t) works in RMrnmJoin
  (and (exists pat RMrnmDigitalPats (rexMatchp pat nm)) t))

(defun RMrnmIsForcedInout (nm)
  (and (exists pat RMrnmForceInout (rexMatchp pat nm)) t))

;; ---------------------------------------------------------------------------
;; Collect ports -> list of (name dir digital?), dir in input/output/inout.
;; (Bus terminals like "D<7:0>" keep the full name; widen the model by hand if
;;  you need per-bit electrical nets -- EEnet vectors are declared the same way.)
;; ---------------------------------------------------------------------------
;; Each port record is (name oadir type dir):
;;   oadir = raw OA terminal direction (input/output/inout) -- reference
;;   type  = "EEnet" (analog) or "logic" (digital), from RMrnmDigitalPats
;;   dir   = effective direction (oadir, or "inout" via RMrnmForceInout)
(defun RMrnmPorts (cv)
  (let (ports)
    (foreach term cv~>terminals
      (let ((nm term~>name) (oad term~>direction) typ dir)
        (setq oad (cond ((equal oad "input")  "input")
                        ((equal oad "output") "output")
                        (t                    "inout")))
        (setq typ (if (RMrnmIsDigital nm) "logic" "EEnet"))
        (setq dir (if (RMrnmIsForcedInout nm) "inout" oad))
        (setq ports (cons (list nm oad typ dir) ports))))
    (reverse ports)))

;; helper: names of ports with effective dir==dir and type==typ, comma-joined
(defun RMrnmJoin (ports dir typ)
  (let (sel)
    (foreach port ports
      (when (and (equal (nth 3 port) dir) (equal (nth 2 port) typ))
        (setq sel (cons (car port) sel))))
    (and sel (buildString (reverse sel) ", "))))

;; ---------------------------------------------------------------------------
;; Emit the EEnet RNM SystemVerilog stub to an already-open port `p`
;; (a file port, or `poport` for the CIW in dry-run).
;; ---------------------------------------------------------------------------
(defun RMrnmEmitSV (p cellName ports)
  (let (allNames grp)
    (fprintf p "// %s -- real-number model (RNM, Cadence EE_pkg::EEnet)\n" cellName)
    (fprintf p "// Auto-scaffolded by RMgenRnm.il; body is SPEC-TODO.\n")
    (fprintf p "import EE_pkg::*;\n")
    (setq allNames (mapcar (lambda (x) (car x)) ports))
    (fprintf p "module %s ( %s );\n" cellName (buildString allNames ",\n    "))
    ;; --- port declarations: analog (EEnet) first, then digital (logic) ---
    (foreach dir '("output" "inout" "input")
      (when (setq grp (RMrnmJoin ports dir "EEnet"))
        (fprintf p "  %-6s EEnet %s;\n" dir grp)))
    (foreach dir '("output" "inout" "input")
      (when (setq grp (RMrnmJoin ports dir "logic"))
        (fprintf p "  %-6s       %s;\n" dir grp)))
    (fprintf p "\n  parameter real ROUT = 1.0e3;  // SPEC-TODO default output R (ohm)\n\n")
    ;; --- stub drivers ---
    (foreach port ports
      (let ((nm (car port)) (typ (nth 2 port)) (dir (nth 3 port)))
        (cond
          ;; analog (EEnet) driving ports
          ((and (equal typ "EEnet") (equal dir "output"))
            (fprintf p "  assign %s = '{V:0.0, I:0.0, R:ROUT};  // TODO\n" nm))
          ((and (equal typ "EEnet") (equal dir "inout"))
            (fprintf p "  assign %s = '{V:`wrealZState, I:`wrealZState, R:`wrealZState};  // TODO\n" nm))
          ;; digital driving ports
          ((and (not (equal typ "EEnet")) (equal dir "output"))
            (fprintf p "  assign %s = 1'b0;  // TODO\n" nm))
          ((and (not (equal typ "EEnet")) (equal dir "inout"))
            (fprintf p "  assign %s = 1'bz;  // TODO\n" nm)))))
    (fprintf p "endmodule\n")
    t))

;; Write the stub to a file on disk.
(defun RMrnmWriteSV (filePath cellName ports)
  (let (p)
    (setq p (outfile filePath))
    (unless p (error "RMgenRnm: cannot write %s\n" filePath))
    (RMrnmEmitSV p cellName ports)
    (close p)
    t))

;; ---------------------------------------------------------------------------
;; Back up an existing master.tag once, then repoint it to verilog.sv.
;; ---------------------------------------------------------------------------
(defun RMrnmRetag (viewDir)
  (let (tagPath bakPath inP outP line)
    (setq tagPath (sprintf nil "%s/master.tag" viewDir))
    (setq bakPath (sprintf nil "%s/master.tag.bak" viewDir))
    (when (and (isFile tagPath) (not (isFile bakPath)))
      (setq inP (infile tagPath)) (setq outP (outfile bakPath))
      (while (gets line inP) (fprintf outP "%s" line))
      (close inP) (close outP))
    (setq outP (outfile tagPath))
    (fprintf outP "-- Master.tag File, Rev:1.0\n%s\n" RMrnmSvFile)
    (close outP)))

;; ---------------------------------------------------------------------------
;; Install the model into the cell's functional view.
;; ---------------------------------------------------------------------------
(defun RMrnmInstall (libName cellName ports)
  (let (libObj libPath viewDir)
    (setq libObj (ddGetObj libName))
    (unless libObj (error "RMgenRnm: library not found: %s\n" libName))
    (setq libPath (ddGetObjWritePath libObj))
    (setq viewDir (sprintf nil "%s/%s/%s" libPath cellName RMrnmViewName))
    (unless (isDir viewDir)
      (unless (isDir (sprintf nil "%s/%s" libPath cellName))
        (createDir (sprintf nil "%s/%s" libPath cellName)))
      (createDir viewDir))
    (RMrnmWriteSV (sprintf nil "%s/%s" viewDir RMrnmSvFile) cellName ports)
    (RMrnmRetag viewDir)
    (ddGetObj libName cellName RMrnmViewName)   ;; nudge DM to re-read
    viewDir))

;; ---------------------------------------------------------------------------
;; Write the spec file consumed by rnm_editor.py: header key=value lines, then
;; a [ports] section of tab-separated  name<TAB>oadir<TAB>type<TAB>dir  rows.
;; ---------------------------------------------------------------------------
(defun RMrnmWriteSpec (specPath libName cellName viewDir svPath ports)
  (let (p)
    (setq p (outfile specPath))
    (unless p (error "RMgenRnm: cannot write spec %s\n" specPath))
    (fprintf p "lib=%s\n"     libName)
    (fprintf p "cell=%s\n"    cellName)
    (fprintf p "view=%s\n"    RMrnmViewName)
    (fprintf p "viewdir=%s\n" viewDir)
    (fprintf p "svfile=%s\n"  RMrnmSvFile)
    (fprintf p "svpath=%s\n"  svPath)
    (fprintf p "[ports]\n")
    (foreach port ports
      (fprintf p "%s\t%s\t%s\t%s\n"
               (nth 0 port) (nth 1 port) (nth 2 port) (nth 3 port)))
    (close p)
    specPath))

;; ipcBeginProcess handlers: stream the editor's stdout/stderr to the CIW, and
;; refresh DM when it exits so Library Manager picks up the new/edited view.
(defun RMrnmPyData (id data) id (printf "%s" data) nil)
(defun RMrnmPyErr  (id data) id (printf "[rnm_editor] %s" data) nil)
(defun RMrnmPyExit (id status)
  id
  (when RMrnmLastTarget
    (ddGetObj (nth 0 RMrnmLastTarget) (nth 1 RMrnmLastTarget) (nth 2 RMrnmLastTarget)))
  (printf "RMgenRnm: editor exited (status %d).%s\n" status
          (if (zerop status) "  Refresh Library Manager to see the view." ""))
  nil)

;; ---------------------------------------------------------------------------
;; F8: extract ports from the selected cell, launch the Python GUI editor.
;; ---------------------------------------------------------------------------
(defun RMgenRnmEdit ()
  (let (win cv libName cellName ports libPath viewDir svPath specPath cmd)
    (setq win (hiGetCurrentWindow))
    (setq cv (RMrnmSourceCV win))
    (unless cv
      (hiGetAttention)
      (warn "RMgenRnm: select one instance, or open a schematic.\n")
      (return nil))
    (setq libName cv~>libName)
    (setq cellName cv~>cellName)
    (setq ports (RMrnmPorts cv))
    (unless ports
      (warn "RMgenRnm: no terminals on %s/%s.\n" libName cellName)
      (return nil))
    (setq libPath (ddGetObjWritePath (ddGetObj libName)))
    (setq viewDir (sprintf nil "%s/%s/%s" libPath cellName RMrnmViewName))
    (setq svPath  (sprintf nil "%s/%s" viewDir RMrnmSvFile))
    (setq specPath (makeTempFileName "/tmp/rmgenrnm"))
    (RMrnmWriteSpec specPath libName cellName viewDir svPath ports)
    (setq RMrnmLastTarget (list libName cellName RMrnmViewName))
    (setq cmd (sprintf nil "%s %s %s %s"
                       RMrnmEnvScrub RMrnmPython RMrnmPyScript specPath))
    (printf "RMgenRnm: editing %s/%s (%d ports); launching GUI...\n"
            libName cellName (length ports))
    (ipcBeginProcess cmd "" 'RMrnmPyData 'RMrnmPyErr 'RMrnmPyExit)
    t))

;; ---------------------------------------------------------------------------
;; Top-level callback. With dryRun (or RMrnmDryRun=t) nothing is written:
;; the model that WOULD be generated is printed to the CIW for review.
;; ---------------------------------------------------------------------------
(defun RMgenRnm (@optional (dryRun RMrnmDryRun))
  (let (win cv libName cellName ports libPath viewDir tagPath)
    (setq win (hiGetCurrentWindow))
    (setq cv (RMrnmSourceCV win))
    (unless cv
      (hiGetAttention)
      (warn "RMgenRnm: select one instance, or open a schematic.\n")
      (return nil))
    (setq libName cv~>libName)
    (setq cellName cv~>cellName)
    (setq ports (RMrnmPorts cv))
    (unless ports
      (warn "RMgenRnm: no terminals on %s/%s.\n" libName cellName)
      (return nil))
    (setq libPath (ddGetObjWritePath (ddGetObj libName)))
    (setq viewDir (sprintf nil "%s/%s/%s" libPath cellName RMrnmViewName))
    (setq tagPath (sprintf nil "%s/master.tag" viewDir))
    (cond
      (dryRun
        (printf "\n;;==== RMgenRnm DRY-RUN: %s/%s (%d ports) ====\n"
                libName cellName (length ports))
        (printf ";; would write : %s/%s\n" viewDir RMrnmSvFile)
        (printf ";; would set   : %s -> %s%s\n" tagPath RMrnmSvFile
                (if (isFile tagPath) "  (current tag backed up to master.tag.bak)" ""))
        (printf ";;---------------------------------------------------------\n")
        (RMrnmEmitSV poport cellName ports)   ;; poport = the CIW output port
        (printf ";;==== end dry-run (nothing written) ====\n\n")
        t)
      (t
        (RMrnmInstall libName cellName ports)
        (printf "RMgenRnm: wrote %s/%s into %s/%s (%d ports). master.tag -> %s\n"
                cellName RMrnmSvFile libName RMrnmViewName (length ports) RMrnmSvFile)
        (printf "  Edit the SPEC-TODO body before relying on the model.\n")
        t))))

;; ---------------------------------------------------------------------------
;; Bind in schematic windows. Change keys to taste.
;;   F9   -> launch the Python GUI editor (set types/dirs + edit body, then Save)
;;   F10  -> DRY-RUN: print the would-be model to the CIW, write nothing
;; (RMgenRnm() with no arg still does a direct no-GUI write, if you want it.)
;; ---------------------------------------------------------------------------
(hiSetBindKey "Schematics" "<Key>F9"   "RMgenRnmEdit()")
(hiSetBindKey "Schematics" "<Key>F10"  "RMgenRnm(t)")
(printf "RMgenRnm.il loaded: F9 = GUI editor ; F10 = dry-run (CIW preview).\n")
