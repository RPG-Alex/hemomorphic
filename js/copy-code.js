document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("pre > code").forEach(codeBlock => {
    const pre = codeBlock.parentElement;

    // create copy button
    const button = document.createElement("button");
    button.className = "copy-button";
    button.type = "button";
    button.innerText = "⿻";

    // copy to clipboard on click
    button.addEventListener("click", async () => {
      const text = codeBlock.innerText;
      try {
        await navigator.clipboard.writeText(text);
        button.innerText = "copied!";
        setTimeout(() => (button.innerText = "⿻"), 1200);
      } catch (err) {
        button.innerText = "error";
      }
    });

    // insert button inside <pre>
    pre.appendChild(button);
    pre.style.position = "relative";
  });
});
