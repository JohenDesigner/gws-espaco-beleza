/* Site Cinematográfico · © 2026 Labrego IA · LBG-SC-2026-v1 */
window.SITE = {
  nome: "GWS Espaço Beleza Cosméticos",
  assinatura: "LBG-SC-20261119-4EE08A647A",

  whatsapp: {
    numero: "5511954840664", // só dígitos, ex.: 5511999998888
    mensagem: "Olá! Vi o site e quero agendar um horário 🤍",
  },

  contato: {
    email: "johenartegrafica@gmail.com",
    // Opcional: chave do Web3Forms (https://web3forms.com). Se vazio, usa FormSubmit.
    web3formsChave: "7fd1863f-4882-43a4-af5a-5fbcd02917f3",
    assunto: "Novo contato pelo site GWS Espaço Beleza Cosméticos",
  },

  // Agenda online (Supabase). A chave anon é pública por natureza; a segurança fica nas regras (RLS) do banco.
  agenda: {
    url: "https://kqonnkaongmsjwdpeuoo.supabase.co",
    chave: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtxb25ua2Fvbmdtc2p3ZHBldW9vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUxMDExMDksImV4cCI6MjExMDY3NzEwOX0.Hpe0hkcHWajv6ezSsVtyKlG0ptNcqQDLb8hgD2N4kds",
    abre: "08:00",
    fecha: "18:00",
    passoMin: 30,
    antecedenciaMin: 120,
    diasFechados: [0, 1], // domingo e segunda
    diasAFrente: 60,
  },

  frames: {
    total: 160, // valor impresso pelo fatiar_frames.sh
    desktop: "assets/frames/desktop/f_{n}.webp?v=1",
    mobile: "assets/frames/mobile/f_{n}.webp?v=1",
  },
};
