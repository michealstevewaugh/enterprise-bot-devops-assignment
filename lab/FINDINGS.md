# Findings — Part 4 debug lab

Fill in one entry per defect you find. Paste the *actual* output you saw —
we cross-check it against your session recording and your git diff, and the
diagnostic path matters more to us than the fix itself.

Before you start investigating, begin recording:
`script -q part4-session.log` (or `asciinema rec part4-session.cast`), and
commit that file alongside this one.

---

## Defect 1

**Symptom** The backend pod is not starting successfully.

**Cause** The pod security context requires a non-root user, but the image specifies the user by name (`nonroot`), so Kubernetes cannot verify it is non-root from the image metadata.

**Fix** Specify the verified numeric UID `65532` using `runAsUser`.

**How I found it** (the sequence of commands/reasoning that led you here):

---

## Defect 2

**Symptom:**

**Cause:**

**Fix:**

**How I found it:**

---

## Defect 3

**Symptom:**

**Cause:**

**Fix:**

**How I found it:**

---

## Defect 4

**Symptom:**

**Cause:**

**Fix:**

**How I found it:**

---

## Defect 5

**Symptom:**

**Cause:**

**Fix:**

**How I found it:**

---

## Defect 6

**Symptom:**

**Cause:**

**Fix:**

**How I found it:**

---

If you ran out of time on any defect, say so here and describe what you would
have tried next — that section is read carefully and counts in your favour.
