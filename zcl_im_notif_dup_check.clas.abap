"! <p class="shorttext synchronized">IW21/IW22: block duplicate breakdown notifications</p>
"! Implementation of classic BAdI NOTIF_EVENT_SAVE, method CHANGE_DATA_AT_SAVE.
"! Filter value of the implementation: QMART = M2. The QMART check in the
"! code is kept as a second guard in case the filter is widened later.
"!
"! Rule: for notification type M2 (breakdown) a second OPEN notification
"! for the same equipment / functional location must not be saved while
"! an earlier one is still open (system status not completed, NOCO).
"!
"! The save is blocked through the BAdI's own protocol
"! (EV_SUBRC <> 0 + EV_MSG*), never with an inline MESSAGE statement,
"! so the standard framework decides how to present the error.
CLASS zcl_im_notif_dup_check DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_ex_notif_event_save.

  PRIVATE SECTION.
    CONSTANTS:
      gc_notif_type_bd TYPE qmart  VALUE 'M2',     " breakdown
      gc_stat_noco     TYPE j_status VALUE 'I0072', " NOCO = completed
      gc_msg_class     TYPE symsgid VALUE 'ZPM',
      gc_msg_no_dup    TYPE symsgno VALUE '001'.

    TYPES: BEGIN OF ty_cand,
             qmnum TYPE qmnum,
             objnr TYPE j_objnr,
           END OF ty_cand.

    METHODS find_open_duplicate
      IMPORTING is_header         TYPE viqmel
      RETURNING VALUE(rv_dup_qmnum) TYPE qmnum.
ENDCLASS.



CLASS zcl_im_notif_dup_check IMPLEMENTATION.

  METHOD if_ex_notif_event_save~change_data_at_save.
    " Filter: only the notification type the rule is defined for
    IF cs_viqmel-qmart <> gc_notif_type_bd.
      RETURN.
    ENDIF.

    " Nothing to compare against
    IF cs_viqmel-equnr IS INITIAL AND cs_viqmel-tplnr IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_dup) = find_open_duplicate( cs_viqmel ).
    IF lv_dup IS INITIAL.
      RETURN.
    ENDIF.

    " Block the save via the BAdI protocol
    ev_subrc = 4.
    ev_msgid = gc_msg_class.
    ev_msgtype = 'E'.
    ev_msgno = gc_msg_no_dup.
    ev_msgv1 = |{ lv_dup ALPHA = OUT }|.
    ev_msgv2 = COND #( WHEN cs_viqmel-equnr IS NOT INITIAL
                       THEN |{ cs_viqmel-equnr ALPHA = OUT }|
                       ELSE cs_viqmel-tplnr ).
    " Message ZPM 001: 'Open breakdown notification &1 already exists for &2'
  ENDMETHOD.


  METHOD find_open_duplicate.
    " Candidate notifications of the same type on the same object,
    " excluding the notification currently being changed (IW22).
    DATA lt_cand TYPE STANDARD TABLE OF ty_cand WITH EMPTY KEY.

    IF is_header-equnr IS NOT INITIAL.
      SELECT qmnum, objnr
        FROM viqmel
        WHERE qmart = @is_header-qmart
          AND qmnum <> @is_header-qmnum
          AND equnr = @is_header-equnr
        ORDER BY qmnum DESCENDING
        INTO TABLE @lt_cand.
    ELSE.
      SELECT qmnum, objnr
        FROM viqmel
        WHERE qmart = @is_header-qmart
          AND qmnum <> @is_header-qmnum
          AND tplnr = @is_header-tplnr
        ORDER BY qmnum DESCENDING
        INTO TABLE @lt_cand.
    ENDIF.
    IF lt_cand IS INITIAL.
      RETURN.
    ENDIF.

    " Active system status: JEST row for NOCO with INACT = ' '.
    " A notification is still open when NO active NOCO status exists.
    SELECT objnr
      FROM jest
      FOR ALL ENTRIES IN @lt_cand
      WHERE objnr = @lt_cand-objnr
        AND stat  = @gc_stat_noco
        AND inact = @abap_false
      INTO TABLE @DATA(lt_completed).
    SORT lt_completed BY objnr.

    LOOP AT lt_cand ASSIGNING FIELD-SYMBOL(<ls_cand>).
      READ TABLE lt_completed TRANSPORTING NO FIELDS
           WITH KEY objnr = <ls_cand>-objnr BINARY SEARCH.
      IF sy-subrc <> 0.
        rv_dup_qmnum = <ls_cand>-qmnum.   " first open one found
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
