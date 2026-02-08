const express = require('express');
const { PDFDocument } = require('pdf-lib');

const app = express();
app.use(express.json());

// Endpoint to generate PDF
app.post('/generate-pdf', async (req, res) => {
  try {
    const { title, content } = req.body;

    // Create a new PDF document
    const pdfDoc = await PDFDocument.create();
    const page = pdfDoc.addPage([600, 400]);
    const { width, height } = page.getSize();

    // Add text to the PDF
    page.drawText(title, { x: 50, y: height - 50, size: 24 });
    page.drawText(content, { x: 50, y: height - 100, size: 12 });

    // Serialize the PDF to bytes
    const pdfBytes = await pdfDoc.save();

    // Send the PDF as a response
    res.setHeader('Content-Type', 'application/pdf');
    res.send(Buffer.from(pdfBytes));
  } catch (error) {
    res.status(500).send({ error: 'Failed to generate PDF' });
  }
});

// Start the server
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});